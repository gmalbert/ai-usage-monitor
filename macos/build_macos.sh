#!/bin/bash
# Build, sign, and optionally install the AI Usage Monitor menu-bar app and
# its widget extension.
#
# Signing happens in two modes, tried in order:
#  1. Automatic signing with an Xcode account ("provisioned"): enables the
#     App Group container so the widget can read live data. Requires an
#     Apple ID signed into Xcode; xcodebuild downloads a team profile with
#     -allowProvisioningUpdates.
#  2. Manual signing with a local development identity or ad-hoc: works
#     without an account, but macOS gates the widget data channels, so the
#     widget shows its empty state.
#
# Usage: ./build_macos.sh [Debug|Release] [--install]
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-Debug}"
INSTALL="${2:-}"

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
    codesign --force --sign "$3" --entitlements "$entitlements" "$target"
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

if build_provisioned && [ -d "$APP" ] && codesign --verify "$APP" 2>/dev/null; then
    echo "Built and signed with automatic provisioning: $APP"
else
    echo "Automatic signing unavailable; building unsigned and signing manually."
    rm -rf "$APP"
    build_unsigned
    if [ ! -d "$APP" ]; then
        echo "Build product not found at $APP" >&2
        exit 1
    fi
    # Prefer a real development identity when present so the App Group container
    # ACL accepts the app; fall back to ad-hoc otherwise.
    if security find-identity -v -p codesigning | grep -q "Apple Development"; then
        IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/')
    else
        IDENTITY="-"
    fi
    # Sign the embedded extension first, then the containing app.
    sign_bundle "$WIDGET" UsageWidget.entitlements "$IDENTITY"
    sign_bundle "$APP" AIUsageMonitor.entitlements "$IDENTITY"
    codesign --verify --deep "$APP"
    echo "Built and signed ($IDENTITY): $APP"
fi

if [ "$INSTALL" = "--install" ]; then
    rm -rf "/Applications/AI Usage Monitor.app"
    ditto "$APP" "/Applications/AI Usage Monitor.app"
    echo "Installed to /Applications"
fi
