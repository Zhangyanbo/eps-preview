#!/usr/bin/env bash
# Install EPS Preview.app to /Applications and register its Quick Look /
# Thumbnail extensions. Ensures Ghostscript is present (installs via
# Homebrew if available).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release/EPSPreview.app"
DEST="/Applications/EPSPreview.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$APP" ] || { echo "error: not built yet. Run: bash scripts/build.sh"; exit 1; }

echo "── Checking Ghostscript ──"
if [ -x /opt/homebrew/bin/gs ] || [ -x /usr/local/bin/gs ] || [ -x /opt/local/bin/gs ] || command -v gs >/dev/null 2>&1; then
  echo "  ✓ Ghostscript found"
else
  if command -v brew >/dev/null 2>&1; then
    echo "  installing Ghostscript via Homebrew…"
    brew install ghostscript
  else
    echo "  ⚠️  Ghostscript not found and Homebrew unavailable."
    echo "     Install Homebrew (https://brew.sh) then: brew install ghostscript"
  fi
fi

echo "── Installing to $DEST ──"
osascript -e 'quit app "EPSPreview"' >/dev/null 2>&1 || true
killall EPSPreview EPSQuickLook EPSThumbnail RenderService >/dev/null 2>&1 || true
# Drop any stray registration of the build-tree copy so the system can't
# serve stale extension code.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "── Registering extensions ──"
"$LSREGISTER" -f -R "$DEST"
open "$DEST"
sleep 3

echo "── Refreshing Finder thumbnails ──"
# Reset only the thumbnail cache (NOT `qlmanage -r`, which de-registers
# third-party extensions) and restart Finder so EPS icons re-render.
qlmanage -r cache >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true

echo
echo "✓ Installed."
echo "  Select any .eps / .ps file in Finder and press the Space bar."
echo
echo "  If the preview doesn't appear immediately, enable it once under:"
echo "  System Settings → General → Login Items & Extensions → Quick Look."
