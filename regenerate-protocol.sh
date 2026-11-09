#!/usr/bin/env bash
# Re-derives the wire schema and the golden conformance vectors from a Java
# source tree. Run this whenever the server's packet definitions change.
#
#   ./regenerate-protocol.sh ../../gravebound/src
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-../../gravebound/src}"
if [[ ! -d "$SRC" ]]; then
	echo "not a directory: $SRC" >&2
	exit 1
fi

python3 tools/gen_schema.py "$SRC"
python3 tools/gen_golden.py "$SRC"
python3 tools/gen_effect_types.py "$SRC"
echo
echo "Schema and golden vectors regenerated. Run ./run-tests.sh to check the"
echo "codec still agrees with the server."
