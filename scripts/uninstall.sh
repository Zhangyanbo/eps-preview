#!/usr/bin/env bash
# Remove EPS Preview.app and unregister its extensions.
set -euo pipefail

DEST="/Applications/EPSPreview.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

killall EPSPreview >/dev/null 2>&1 || true
pluginkit -r "$DEST/Contents/PlugIns/EPSQuickLook.appex" >/dev/null 2>&1 || true
pluginkit -r "$DEST/Contents/PlugIns/EPSThumbnail.appex" >/dev/null 2>&1 || true
"$LSREGISTER" -u "$DEST" >/dev/null 2>&1 || true
rm -rf "$DEST"
rm -rf "$HOME/Library/Containers/com.zhangyanbo.EPSPreview"* 2>/dev/null || true

killall Finder >/dev/null 2>&1 || true
echo "✓ EPS Preview uninstalled."
