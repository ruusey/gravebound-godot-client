#!/usr/bin/env python3
"""
Generate scripts/net/schema.gd from an GraveBound Java source tree.

The wire format is declared in Java two different ways, and both are read here:

1. @SerializableField(order, type, isCollection) annotations on fields. The
   *order* argument is the wire order. Every packet uses this form.
2. A StreamCodec.builder(...) chain held in a `static final CODEC`, where
   declaration order *is* wire order. v0.9.0 moved nine wire entities onto
   this form -- NetBullet, NetGameItem, NetStats and friends.

Form 2 also brings masked sections: `.maskedSections(...)` writes a single
mask byte and then only those field groups whose bit is set. That is emitted
as a ["_mask", "mask", false, [[bit, [fields...]], ...]] entry, which the
codec understands.

Rather than hand-transcribing ~50 packets and ~20 wire entities into GDScript
(and re-transcribing them every time the server changes), we read the layout
straight out of the Java source and emit a table the generic codec walks.

Usage:
    python3 tools/gen_schema.py <java-src-root> [-o scripts/net/schema.gd]

Example:
    python3 tools/gen_schema.py ../../gravebound/src
"""
import argparse
import os
import re
import sys
from datetime import datetime, timezone

# Java serializer class -> codec primitive name. Anything not in this map is
# treated as a nested @Streamable entity and recursed into.
PRIMITIVES = {
    "SerializableByte": "byte",
    "SerializableBoolean": "bool",
    "SerializableShort": "short",
    "SerializableInt": "int",
    "SerializableLong": "long",
    "SerializableFloat": "float",
    "SerializableString": "string",
}

CLASS_RE = re.compile(r"^\s*(?:public\s+|final\s+|abstract\s+)*class\s+(\w+)", re.M)
PACKET_ID_RE = re.compile(r"@PacketId\s*\(\s*packetId\s*=\s*\(\s*byte\s*\)\s*(-?\d+)\s*\)")
FIELD_RE = re.compile(
    r"@SerializableField\s*\(([^)]*)\)\s*"          # annotation args
    r"(?:@\w+(?:\([^)]*\))?\s*)*"                    # any extra annotations
    r"(?:public|private|protected)\s+"
    r"(?:static\s+|final\s+|transient\s+)*"
    r"([\w.]+(?:\s*\[\s*\])?)\s+"                    # java type
    r"(\w+)\s*[;=]"                                   # field name
)
ORDER_RE = re.compile(r"order\s*=\s*(\d+)")
TYPE_RE = re.compile(r"type\s*=\s*([\w.]+)\.class")
COLLECTION_RE = re.compile(r"isCollection\s*=\s*true")

# --- StreamCodec builder form (v0.9.0+) ----------------------------------
# Builder method -> wire type. `nested`/`list` name their type in the first
# argument; `shortArray` is a short collection; `maskedSections` is special.
BUILDER_PRIMITIVES = {
    "int8": "byte",
    "bool": "bool",
    "int16": "short",
    "int32": "int",
    "int64": "long",
    "float32": "float",
    "utf": "string",
}
BUILDER_START_RE = re.compile(r"StreamCodec\s*\.\s*builder\s*\(")
# `private static final byte SECT_WAVY = 0x01;`
BIT_CONST_RE = re.compile(
    r"static\s+final\s+(?:byte|short|int)\s+(\w+)\s*=\s*(0[xX][0-9A-Fa-f]+|\d+)\s*;")
# Declared instance fields, used to recover a field's exact spelling from its
# accessor: Lombok turns `dX` into `getDX()`, which does not decapitalize back.
FIELD_DECL_RE = re.compile(
    r"^[ \t]*(?:private|protected|public)\s+"
    r"(?!static\b)(?:final\s+|transient\s+|volatile\s+)*"
    r"[\w.$]+(?:\s*<[^;=]*>)?(?:\s*\[\s*\])?\s+(\w+)\s*[;=]", re.M)


def _match_paren(text, index):
    """Index of the character just past the ')' matching the '(' at `index`."""
    depth = 0
    while index < len(text):
        char = text[index]
        if char == '"':
            index += 1
            while index < len(text) and text[index] != '"':
                index += 2 if text[index] == "\\" else 1
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
        index += 1
    raise ValueError("unbalanced parentheses in builder chain")


def split_chain(text):
    """[(method, args)] for every `.method(...)` at paren depth 0 of `text`."""
    calls = []
    index = 0
    while index < len(text):
        if text[index] == ".":
            match = re.match(r"\.\s*(\w+)\s*\(", text[index:])
            if match:
                open_paren = index + match.end() - 1
                close = _match_paren(text, open_paren)
                calls.append((match.group(1), text[open_paren + 1:close - 1]))
                index = close
                continue
        index += 1
    return calls


def split_args(text):
    """Top-level comma split, ignoring commas nested in parens or brackets.

    Angle brackets are deliberately not tracked: the only `>` that shows up in
    a builder argument is the arrow of a lambda, and treating it as a closer
    drives the depth negative and swallows every later comma.
    """
    parts, depth, current = [], 0, []
    for char in text:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    tail = "".join(current).strip()
    if tail:
        parts.append(tail)
    return parts


def accessor_field(ref, declared):
    """`NetBullet::getDX` -> `dX`, using the declared fields for exact case."""
    method = ref.split("::")[-1].strip()
    stem = method
    for prefix in ("get", "is", "set"):
        if method.startswith(prefix) and len(method) > len(prefix):
            stem = method[len(prefix):]
            break
    return declared.get(stem.lower(), stem[0].lower() + stem[1:])


def parse_builder_fields(chain, declared, bits, cls):
    """Walk a builder chain into [(name, wire_type, is_collection, sections)]."""
    fields = []
    for method, args in split_chain(chain):
        arg_list = split_args(args)
        if method in BUILDER_PRIMITIVES:
            fields.append((accessor_field(arg_list[0], declared),
                           BUILDER_PRIMITIVES[method], False, None))
        elif method == "nested":
            fields.append((accessor_field(arg_list[1], declared),
                           arg_list[0].split(".")[0].strip(), False, None))
        elif method == "list":
            fields.append((accessor_field(arg_list[1], declared),
                           arg_list[0].split(".")[0].strip(), True, None))
        elif method == "shortArray":
            fields.append((accessor_field(arg_list[0], declared), "short", True, None))
        elif method == "maskedSections":
            sections = parse_masked_sections(args, declared, bits, cls)
            if sections:
                fields.append(("_mask", "mask", False, sections))
        elif method in ("builder", "build"):
            continue
        else:
            print(f"  ! {cls}: unknown builder method .{method}(), skipped", file=sys.stderr)
    return fields


def parse_masked_sections(args, declared, bits, cls):
    """`.maskedSections(s -> s.section(BIT, pred, f -> f...))` -> [(bit, fields)]."""
    if "->" not in args:
        return []
    sections = []
    for method, section_args in split_chain(args.split("->", 1)[1]):
        if method != "section":
            continue
        parts = split_args(section_args)
        if len(parts) < 3 or "->" not in parts[2]:
            print(f"  ! {cls}: unparsable .section(...), skipped", file=sys.stderr)
            continue
        token = parts[0].strip()
        if token in bits:
            bit = bits[token]
        elif re.fullmatch(r"(?:\(\s*byte\s*\)\s*)?(0[xX][0-9A-Fa-f]+|\d+)", token):
            bit = int(re.sub(r"^\(\s*byte\s*\)\s*", "", token), 0)
        else:
            print(f"  ! {cls}: section bit '{token}' unresolved, skipped", file=sys.stderr)
            continue
        fields = parse_builder_fields(parts[2].split("->", 1)[1], declared, bits, cls)
        sections.append((bit, fields))
    return sections


def parse_file(path):
    """Return (class_name, packet_id_or_None, fields) or None.

    `fields` is an ordered [(name, wire_type, is_collection, sections)] list,
    where `sections` is None except on a masked-section block.
    """
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    if "@Streamable" not in src:
        return None

    cls = CLASS_RE.search(src)
    if not cls:
        return None
    name = cls.group(1)

    pid = PACKET_ID_RE.search(src)
    packet_id = int(pid.group(1)) if pid else None

    if "@SerializableField" in src:
        fields = parse_annotated_fields(src, name)
    else:
        fields = parse_codec_fields(src, name)

    # A packet with an id but no body is legitimate (DeathAckPacket,
    # LoginAckPacket): it still has to be in the table, or the client counts
    # every one it receives as an unknown packet.
    if not fields and packet_id is None:
        return None
    return name, packet_id, fields


def parse_annotated_fields(src, name):
    """Fields from @SerializableField(order=..., type=...) annotations."""
    fields = []
    for attrs, _java_type, field_name in FIELD_RE.findall(src):
        order_m = ORDER_RE.search(attrs)
        type_m = TYPE_RE.search(attrs)
        if not order_m or not type_m:
            print(f"  ! {name}.{field_name}: missing order/type, skipped", file=sys.stderr)
            continue
        ser = type_m.group(1).rsplit(".", 1)[-1]
        wire_type = PRIMITIVES.get(ser, ser)
        fields.append((int(order_m.group(1)), wire_type, field_name,
                       bool(COLLECTION_RE.search(attrs))))
    if not fields:
        return []
    fields.sort(key=lambda f: f[0])

    orders = [f[0] for f in fields]
    if len(set(orders)) != len(orders):
        print(f"  ! {name}: DUPLICATE @SerializableField order values {orders}", file=sys.stderr)
    return [(fname, wire, coll, None) for _o, wire, fname, coll in fields]


def parse_codec_fields(src, name):
    """Fields from a `static final StreamCodec<X> CODEC = builder()...` chain."""
    start = BUILDER_START_RE.search(src)
    if not start:
        return []
    # The chain runs from the builder's closing paren to its matching .build().
    chain_start = _match_paren(src, start.end() - 1)
    depth, index = 0, chain_start
    while index < len(src):
        if src[index] == "(":
            depth += 1
        elif src[index] == ")":
            depth -= 1
        elif src[index] == ";" and depth == 0:
            break
        index += 1
    chain = src[chain_start:index]

    declared = {m.lower(): m for m in FIELD_DECL_RE.findall(src)}
    bits = {m: int(v, 0) for m, v in BIT_CONST_RE.findall(src)}
    return parse_builder_fields(chain, declared, bits, name)


def gd_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src_root", help="path to the Java src tree (e.g. .../gravebound-legacy/src)")
    ap.add_argument("-o", "--out", default=None, help="output .gd path")
    args = ap.parse_args()

    src_root = os.path.abspath(args.src_root)
    if not os.path.isdir(src_root):
        sys.exit(f"not a directory: {src_root}")

    out_path = args.out or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "net", "schema.gd"
    )

    parsed = {}
    for dirpath, _dirs, files in os.walk(src_root):
        for f in files:
            if not f.endswith(".java"):
                continue
            result = parse_file(os.path.join(dirpath, f))
            if result:
                name, packet_id, fields = result
                if name in parsed:
                    print(f"  ! duplicate class name {name}, keeping first", file=sys.stderr)
                    continue
                parsed[name] = (packet_id, fields)

    packets = {n: v for n, v in parsed.items() if v[0] is not None}
    entities = {n: v for n, v in parsed.items() if v[0] is None}

    # Every non-primitive field type must resolve to a known entity, or the
    # codec will hit an unknown type at runtime instead of at generation time.
    known = set(parsed)
    missing = set()

    def check(owner, fields):
        for fname, wire_type, _coll, sections in fields:
            if wire_type == "mask":
                for _bit, section_fields in sections:
                    check(owner, section_fields)
            elif wire_type not in PRIMITIVES.values() and wire_type not in known:
                missing.add(f"{owner}.{fname} -> {wire_type}")

    for name, (_pid, fields) in parsed.items():
        check(name, fields)
    if missing:
        print("  ! unresolved field types (codec will fail on these):", file=sys.stderr)
        for m in sorted(missing):
            print(f"      {m}", file=sys.stderr)

    by_id = {}
    for name, (pid, _f) in packets.items():
        by_id.setdefault(pid, []).append(name)
    for pid, names in sorted(by_id.items()):
        if len(names) > 1:
            print(f"  ! packet id {pid} claimed by {names}", file=sys.stderr)

    lines = []
    w = lines.append
    w("# GENERATED FILE - DO NOT EDIT BY HAND.")
    w("#")
    w("# Regenerate with:")
    w("#   python3 tools/gen_schema.py <java-src-root>")
    w("#")
    w(f"# Source tree : {src_root}")
    w(f"# Generated   : {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')}")
    w(f"# Packets     : {len(packets)}")
    w(f"# Entities    : {len(entities)}")
    w("#")
    w("# Field tuples are [name, wire_type, is_collection]; list order is wire order.")
    w("# Primitive wire types are byte, bool, short, int, long, float and string;")
    w("# anything else names an entry in ENTITIES.")
    w("#")
    w("# A tuple of [name, \"mask\", false, sections] is a masked-section block: one")
    w("# mask byte, then the fields of each section whose bit is set, in order.")
    w("# sections is [[bit, [field tuples]], ...].")
    w("class_name NetSchema")
    w("")
    w(f'const SOURCE_TREE := "{gd_escape(src_root)}"')
    w("")

    w("# packet id -> class name")
    w("const PACKET_NAMES := {")
    for pid in sorted(by_id):
        w(f'\t{pid}: "{by_id[pid][0]}",')
    w("}")
    w("")

    w("# class name -> packet id")
    w("const PACKET_IDS := {")
    for name in sorted(packets):
        w(f'\t"{name}": {packets[name][0]},')
    w("}")
    w("")

    def emit_fields(fields, indent):
        pad = "\t" * indent
        for fname, wire_type, is_coll, sections in fields:
            if wire_type == "mask":
                w(f'{pad}["{fname}", "mask", false, [')
                for bit, section_fields in sections:
                    w(f"{pad}\t[{bit}, [")
                    emit_fields(section_fields, indent + 2)
                    w(f"{pad}\t]],")
                w(f"{pad}]],")
            else:
                w(f'{pad}["{fname}", "{wire_type}", {str(is_coll).lower()}],')

    def emit_table(const_name, table, comment):
        w(f"# {comment}")
        w(f"const {const_name} := {{")
        for name in sorted(table):
            w(f'\t"{name}": [')
            emit_fields(table[name][1], 2)
            w("\t],")
        w("}")
        w("")

    emit_table("PACKETS", packets, "packet class name -> ordered field list")
    emit_table("ENTITIES", entities, "nested wire-entity class name -> ordered field list")

    w("static func fields_for(type_name: String) -> Array:")
    w("\tif PACKETS.has(type_name):")
    w("\t\treturn PACKETS[type_name]")
    w("\tif ENTITIES.has(type_name):")
    w("\t\treturn ENTITIES[type_name]")
    w("\treturn []")
    w("")
    w("static func is_known(type_name: String) -> bool:")
    w("\treturn PACKETS.has(type_name) or ENTITIES.has(type_name)")
    w("")

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))

    print(f"wrote {out_path}: {len(packets)} packets, {len(entities)} entities")
    print(f"  ids: {', '.join(str(i) for i in sorted(by_id))}")


if __name__ == "__main__":
    main()
