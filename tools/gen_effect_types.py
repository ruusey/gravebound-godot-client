#!/usr/bin/env python3
"""
Generate scripts/net/effect_type.gd from an GraveBound Java source tree.

CreateEffectPacket's `effectType` is a bare short on the wire; the names live
only as `public static final short EFFECT_<NAME> = <id>;` constants on the
packet class. They are read out of the Java here, as the packet layouts are
by gen_schema.py, so the client names a type exactly as the server does and
a retired id (48-50 on v0.9.0) simply has no name.

Usage:
    python3 tools/gen_effect_types.py <java-src-root> [-o scripts/net/effect_type.gd]
"""
import argparse
import os
import re
import sys

CONSTANT = re.compile(r"public\s+static\s+final\s+short\s+EFFECT_(\w+)\s*=\s*(\d+)\s*;")


def find_packet(src_root):
    for root, _dirs, files in os.walk(src_root):
        if "CreateEffectPacket.java" in files:
            return os.path.join(root, "CreateEffectPacket.java")
    sys.exit(f"CreateEffectPacket.java not found under {src_root}")


def read_types(path):
    src = open(path, encoding="utf-8", errors="replace").read()
    types = [(name, int(value)) for name, value in CONSTANT.findall(src)]
    ids = [value for _name, value in types]
    if not types:
        sys.exit(f"no EFFECT_ constants in {path}")
    if len(set(ids)) != len(ids):
        sys.exit(f"duplicate effect ids in {path}: {sorted(ids)}")
    return sorted(types, key=lambda t: t[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src_root", help="path to the Java src tree (e.g. ../../gravebound/src)")
    ap.add_argument("-o", "--out", default=None, help="output .gd path")
    args = ap.parse_args()

    src_root = os.path.abspath(args.src_root)
    if not os.path.isdir(src_root):
        sys.exit(f"not a directory: {src_root}")
    here = os.path.dirname(os.path.abspath(__file__))
    out_path = args.out or os.path.join(here, "..", "scripts", "net", "effect_type.gd")

    types = read_types(find_packet(src_root))
    lines = [
        "# GENERATED FILE - DO NOT EDIT BY HAND.",
        "#",
        "# Regenerate with:",
        "#   python3 tools/gen_effect_types.py <java-src-root>",
        "#",
        "# The EFFECT_ constants on CreateEffectPacket.java: what the wire's",
        "# `effectType` short means. An id missing here is retired on the server.",
        "class_name EffectType",
        "extends RefCounted",
        "",
        "enum {",
    ]
    lines += [f"\t{name} = {value}," for name, value in types]
    lines += ["}", "", "const NAMES := {"]
    lines += [f'\t{value}: "{name}",' for name, value in types]
    lines += ["}", ""]

    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {out_path}: {len(types)} effect types, ids {types[0][1]}..{types[-1][1]}")


if __name__ == "__main__":
    main()
