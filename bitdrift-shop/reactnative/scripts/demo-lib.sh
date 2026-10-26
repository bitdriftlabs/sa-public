# Shared helpers for ios-4-stop-app.sh and ios-foreground-cycle.sh: this app's bundle id on top of the
# shared simctl/devicectl driver.
#
# Must match PRODUCT_BUNDLE_IDENTIFIER in ios/ShopDemoRN.xcodeproj. Carries a ".rn." segment so it can never
# collide with the native iOS app's bundle id (ai.bitdrift.shop.ios) or the native Android app's
# applicationId — see android-1-setup.sh's header comment for the collision this used to cause.
BUNDLE_ID="${BUNDLE_ID:-ai.bitdrift.rn.shop}"

# shellcheck source=../../scripts/lib/driver-simctl.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/driver-simctl.sh"
