#!/bin/zsh
set -euo pipefail

# Takes the App Store screenshots from the demo family on the two sizes App Store Connect
# requires: a 6.9" iPhone and a 13" iPad. Each shot is staged with launch arguments that only
# Local builds read (see Shared/Views/ScreenshotSetup.swift), so no tapping is involved.
#
#   ./scripts/take-screenshots.sh            writes PNGs to docs/app-store/screenshots/
#
# Override the simulators with IPHONE=<name or udid> IPAD=<name or udid>.

PROJECT_ROOT="${0:A:h:h}"
OUT="$PROJECT_ROOT/docs/app-store/screenshots"
IPHONE="${IPHONE:-iPhone 16 Pro Max}"
IPAD="${IPAD:-iPad Pro 13-inch (M4)}"
BUNDLE_ID=com.happymama.HappyMama
APP="$PROJECT_ROOT/build/screenshots/Build/Products/Local-iphonesimulator/HappyMama.app"

# name  member  section
SHOTS=(
    "1-kid-chores Ava chores"
    "2-kid-rewards Ava rewards"
    "3-parent-review Mama review"
    "4-parent-chores Mama chores"
    "5-family Mama family"
)

cd "$PROJECT_ROOT"
[[ -d HappyMama.xcodeproj ]] || xcodegen generate

print "Building the Local app for the simulator."
xcodebuild -project HappyMama.xcodeproj -scheme HappyMama-iOS-Local -configuration Local \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/screenshots \
    CODE_SIGNING_ALLOWED=NO build -quiet

shoot() {
    local device="$1" folder="$2"
    print "Shooting on $device."
    xcrun simctl boot "$device" 2>/dev/null || true
    xcrun simctl bootstatus "$device" -b >/dev/null
    xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
        --cellularMode active --cellularBars 4 --wifiBars 3
    xcrun simctl ui "$device" appearance light
    # A fresh install, so the demo family is loaded with today's dates.
    xcrun simctl uninstall "$device" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$device" "$APP"
    mkdir -p "$OUT/$folder"
    for shot in "${SHOTS[@]}"; do
        local name="${shot%% *}" rest="${shot#* }"
        local member="${rest%% *}" section="${rest#* }"
        xcrun simctl terminate "$device" "$BUNDLE_ID" 2>/dev/null || true
        xcrun simctl launch "$device" "$BUNDLE_ID" -screenshotMember "$member" -screenshotSection "$section" >/dev/null
        sleep 4
        xcrun simctl io "$device" screenshot "$OUT/$folder/$name.png" >/dev/null 2>&1
        print "  $folder/$name.png"
    done
    xcrun simctl status_bar "$device" clear
}

shoot "$IPHONE" iphone-6.9
shoot "$IPAD" ipad-13
print "Done. Upload the folders under $OUT to App Store Connect."
