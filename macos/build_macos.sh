#!/bin/bash
# Build, sign, and optionally install the AI Usage Monitor menu-bar app and
# its widget extension.
#
# Signing happens in two modes:
#  1. Automatic signing with an Xcode account ("--provisioned"): enables the
#     App Group container so the widget can read live data through the
#     standard channel. Requires an Apple ID signed into Xcode and an
#     unlocked login keychain; xcodebuild downloads a team profile with
#     -allowProvisioningUpdates.
#  2. Local ad-hoc signing (default): works without an account and never
#     touches the keychain. The widget reads data through a JSON file the
#     app publishes inside the widget's own container.
#
# Usage: ./build_macos.sh [Debug|Release] [--install] [--provisioned]
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-Debug}"
MODE="${2:-}"
INSTALL="${3:-}"

# Automatic signing is only attempted with an explicit --provisioned flag:
# on a machine with a locked login keychain (or no Xcode account) the
# attempt opens keychain password prompts on the user's screen.
PROVISIONED=0
for arg in "$@"; do
    [ "$arg" = "--provisioned" ] && PROVISIONED=1
done

if [ ! -d AIUsageMonitor.xcodeproj ]; then
    xcodegen generate --spec project.yml
fi

APP="build/DerivedData/Build/Products/$CONFIGURATION/AIUsageMonitor.app"
WIDGET="$APP/Contents/PlugIns/UsageWidget.appex"

build_unsigned() {
    xcodebuild -project AIUsageMonitor.xcodeproj \
        -scheme AIUsageMonitor \
        -configuration "$CONFIGURATION" \
        build CODE_SIGNING_ALLOWED=NO \
        -derivedDataPath build/DerivedData \
        | tail -1
}

sign_bundle() {
    local target="$1"
    local entitlements="$2"
    # Try the requested identity, but fall back to ad-hoc signing when it
    # cannot be used — e.g. when the login keychain holding the identity's
    # private key is locked. Ad-hoc ("Sign to Run Locally") is enough to run
    # locally; the widget container-file channel does not depend on the
    # signing identity.
    if ! codesign --force --sign "$3" --entitlements "$entitlements" "$target" 2>/dev/null; then
        echo "Signing with '$3' failed (locked keychain?); falling back to ad-hoc."
        codesign --force --sign "-" --entitlements "$entitlements" "$target"
    fi
}

build_provisioned() {
    echo "Trying automatic signing with an Xcode account…"
    if xcodebuild -project AIUsageMonitor.xcodeproj \
        -scheme AIUsageMonitor \
        -configuration "$CONFIGURATION" \
        build CODE_SIGN_STYLE=Automatic \
        -allowProvisioningUpdates \
        -derivedDataPath build/DerivedData 2>&1 | tail -2; then
        return 0
    fi
    return 1
}

if [ "$PROVISIONED" = "1" ] && build_provisioned && [ -d "$APP" ] && codesign --verify "$APP" 2>/dev/null; then
    echo "Built and signed with automatic provisioning: $APP"
else
    echo "Building with local signing (use --provisioned to try automatic signing with an Xcode account)."
    rm -rf "$APP"
    build_unsigned
    if [ ! -d "$APP" ]; then
        echo "Build product not found at $APP" >&2
        exit 1
    fi
    # Always sign ad-hoc here: attempting to sign with a development identity
    # reaches into the login keychain for its private key, which pops a
    # password prompt whenever the keychain is locked — and the App Group
    # channel only works for provisioned builds anyway.
    sign_bundle "$WIDGET" UsageWidget.entitlements "-"
    sign_bundle "$APP" AIUsageMonitor.entitlements "-"
    codesign --verify --deep "$APP"
    echo "Built and signed (ad-hoc): $APP"
fi

if [ "$INSTALL" = "--install" ] || [ "$MODE" = "--install" ]; then
    rm -rf "/Applications/AI Usage Monitor.app"
    ditto "$APP" "/Applications/AI Usage Monitor.app"
    echo "Installed to /Applications"
fi
