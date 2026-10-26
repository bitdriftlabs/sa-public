#!/usr/bin/env bash
# Fail if any checked-in generated constants differ from what spec/*.yaml produces.
# Add one line per platform as each adopts generated constants.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/tools/codegen/run.sh"
"$RUN" kotlin "$ROOT/android/app/src/main/java/ai/bitdrift/shop/generated" ai.bitdrift.shop.generated --check
"$RUN" swift "$ROOT/ios/BitdriftShop/Generated" --check
"$RUN" ts "$ROOT/reactnative/src/generated" --check
"$RUN" dart "$ROOT/flutter/lib/generated" --check
"$ROOT/tools/codegen/.venv/bin/python" "$ROOT/tools/journey/golden.py" --check
