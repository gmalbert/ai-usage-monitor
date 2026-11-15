#!/bin/bash
# Build, ad-hoc sign, and optionally install the AI Usage Monitor menu-bar
# app and its widget extension. Signing requires no Apple developer account;
# for distribution, re-sign with a Developer ID and notarize.
#
# Usage: ./build_macos.sh [Debug|Release] [--install]
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-Debug}"
INSTALL="${2:-}"

if [ ! -d AIUsageMonitor.xcodeproj ]; then
    xcodegen generate --spec project.yml
fi

xcodebuild -project AIUsageMonitor.xcodeproj \
    -scheme AIUsageMonitor \
    -configuration "$CONFIGURATION" \
    build CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath build/DerivedData \
    | tail -1

APP="build/DerivedData/Build/Products/$CONFIGURATION/AIUsageMonitor.app"
WIDGET="$APP/Contents/PlugIns/UsageWidget.appex"

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

sign_bundle() {
    local target="$1"
    local entitlements="$2"
    codesign --force --sign "$IDENTITY" --entitlements "$entitlements" "$target"
}

# Sign the embedded extension first, then the containing app.
sign_bundle "$WIDGET" UsageWidget.entitlements
sign_bundle "$APP" AIUsageMonitor.entitlements

codesign --verify --deep "$APP"
echo "Built and signed ($IDENTITY): $APP"

if [ "$INSTALL" = "--install" ]; then
    rm -rf "/Applications/AI Usage Monitor.app"
    ditto "$APP" "/Applications/AI Usage Monitor.app"
    sign_bundle "/Applications/AI Usage Monitor.app/Contents/PlugIns/UsageWidget.appex" UsageWidget.entitlements
    sign_bundle "/Applications/AI Usage Monitor.app" AIUsageMonitor.entitlements
    echo "Installed to /Applications"
fi
