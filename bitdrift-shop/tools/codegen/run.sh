#!/usr/bin/env bash
# Run the spec codegen with PyYAML from a local venv (created on first use).
# Usage: tools/codegen/run.sh <language> <output-dir> [package] [--check]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/.venv"
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet pyyaml
fi
exec "$VENV/bin/python" "$HERE/codegen.py" "$@"
