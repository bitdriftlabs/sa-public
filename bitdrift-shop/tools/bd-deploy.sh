#!/usr/bin/env bash
# Deploy the bd-shop workflows and dashboards for one app. Dry run unless --apply is given.
#   tools/bd-deploy.sh ai.bitdrift.shop            # Android app, plan only
#   tools/bd-deploy.sh ai.bitdrift.shop --apply    # create what is missing (asks first)
#   tools/bd-deploy.sh ai.bitdrift.shop.ios --apply
# See tools/bd-deploy.py --help for options.
set -euo pipefail
command -v bd >/dev/null || { echo "bd CLI not found — brew install bitdriftlabs/bd/bd" >&2; exit 1; }
exec python3 -I "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bd-deploy.py" "$@"
