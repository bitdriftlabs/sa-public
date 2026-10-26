#!/usr/bin/env bash
# Regenerate every platform's constants from spec/*.yaml. check.sh is the CI twin.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUN="$ROOT/tools/codegen/run.sh"
"$RUN" kotlin "$ROOT/android/app/src/main/java/ai/bitdrift/shop/generated" ai.bitdrift.shop.generated
"$RUN" swift "$ROOT/ios/BitdriftShop/Generated"
"$RUN" ts "$ROOT/reactnative/src/generated"
"$RUN" dart "$ROOT/flutter/lib/generated"
"$ROOT/tools/codegen/.venv/bin/python" "$ROOT/tools/journey/golden.py"
"$RUN" sh "$ROOT/scripts/lib/generated"
