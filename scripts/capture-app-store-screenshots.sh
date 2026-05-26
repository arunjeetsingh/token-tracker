#!/usr/bin/env bash
# capture-app-store-screenshots.sh
#
# Captures TokenCounter screenshots in App Store-required sizes:
#   - 6.9" (iPhone 17 Pro Max) — 1320x2868 — required
#   - 6.5" (iPhone 11 Pro Max) — 1242x2688 — required for back-compat
#
# Uses iOS Simulator + DemoMode launch arg. No real API calls; no PII.
# Screenshots land in docs/app-store-screenshots/{6.9inch,6.5inch}/.
#
# Pre-reqs:
#   - Xcode 26 installed
#   - Simulators named exactly:
#       "iPhone 17 Pro Max"
#       "iPhone 11 Pro Max (Screenshots)"
#   - App bundle id: ai.openclaw.tokentracker.TokenTracker
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/ios"

BUNDLE_ID="ai.openclaw.tokentracker.TokenTracker"
OUT_BASE="$REPO_ROOT/docs/app-store-screenshots"
mkdir -p "$OUT_BASE"

# Ensure xcodeproj is fresh
xcodegen generate >/dev/null

build_and_install() {
  local sim_name="$1"
  local out_dir="$2"
  echo "==> $sim_name -> $out_dir"

  local udid
  udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
target = sys.argv[1]
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['name'] == target and d.get('isAvailable', True):
            print(d['udid']); sys.exit(0)
sys.exit('no simulator named \"%s\" found' % target)
" "$sim_name")

  echo "  udid=$udid"
  xcrun simctl boot "$udid" 2>/dev/null || true
  # Give it a few seconds to come up
  xcrun simctl bootstatus "$udid" -b >/dev/null

  # Build to this simulator
  xcodebuild -project TokenTracker.xcodeproj \
    -scheme TokenTracker \
    -configuration Release \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath build/screenshot-derived \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

  local app_path
  app_path="build/screenshot-derived/Build/Products/Release-iphonesimulator/TokenTracker.app"
  xcrun simctl install "$udid" "$app_path"

  mkdir -p "$out_dir"

  # 1. Dashboard — loaded state via DemoMode (default screen = dashboard)
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" -DemoMode YES >/dev/null
  sleep 4
  xcrun simctl io "$udid" screenshot "$out_dir/01-dashboard.png"

  # 2. Onboarding — forced via -DemoModeScreen onboarding. Skips the
  #    Keychain entirely so we don't get the -34018 errSecMissingEntitlement
  #    bug that breaks unsigned simulator KeychainStore reads.
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$udid" "$BUNDLE_ID" -DemoMode YES -DemoModeScreen onboarding >/dev/null
  sleep 4
  xcrun simctl io "$udid" screenshot "$out_dir/02-onboarding.png"

  echo "  captured -> $out_dir"
  echo
}

build_and_install "iPhone 17 Pro Max" "$OUT_BASE/6.9inch"
build_and_install "iPhone 11 Pro Max (Screenshots)" "$OUT_BASE/6.5inch"

# Render marketing caption overlays into the captioned/ subfolders.
# These are the files we actually upload to App Store Connect.
echo "==> adding caption overlays"
python3 "$REPO_ROOT/scripts/add-caption-overlays.py"

echo
echo "raw screenshots:        $OUT_BASE/{6.5inch,6.9inch}/*.png"
echo "captioned (for upload): $OUT_BASE/{6.5inch,6.9inch}/captioned/*.png"
ls -la "$OUT_BASE"/*/ "$OUT_BASE"/*/captioned/ 2>/dev/null
