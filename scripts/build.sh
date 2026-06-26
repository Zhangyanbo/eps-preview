#!/usr/bin/env bash
# Build EPS Preview.app (host + Quick Look + Thumbnail extensions + render
# XPC service) and ad-hoc sign it. No Apple Developer Program account needed.
#
# Idempotent — safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen not found. Install with: brew install xcodegen"; exit 1; }

echo "── (1/5) Generating Xcode project ──"
xcodegen generate

echo
echo "── (2/5) Building (Release) ──"
if command -v xcbeautify >/dev/null 2>&1; then BEAUTIFY=(xcbeautify); else BEAUTIFY=(cat); fi
set -o pipefail
xcodebuild \
  -project EPSPreview.xcodeproj \
  -scheme EPSPreview \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_STYLE=Manual \
  build | "${BEAUTIFY[@]}"

APP="build/Build/Products/Release/EPSPreview.app"
SERVICE="build/Build/Products/Release/RenderService.xpc"
[ -d "$APP" ]     || { echo "error: build produced no $APP"; exit 1; }
[ -d "$SERVICE" ] || { echo "error: build produced no $SERVICE"; exit 1; }

echo
echo "── (3/5) Embedding RenderService.xpc into each extension ──"
# A sandboxed extension can only reach an XPC service that lives inside its
# own bundle (Contents/XPCServices). So each extension carries its own copy.
embed_service() {
  local host_dir="$1"
  mkdir -p "$host_dir/Contents/XPCServices"
  rm -rf "$host_dir/Contents/XPCServices/RenderService.xpc"
  cp -R "$SERVICE" "$host_dir/Contents/XPCServices/"
  echo "  → $host_dir/Contents/XPCServices/RenderService.xpc"
}
embed_service "$APP/Contents/PlugIns/EPSQuickLook.appex"
embed_service "$APP/Contents/PlugIns/EPSThumbnail.appex"
embed_service "$APP"

echo
echo "── (3.5/5) Pinning NSExtension blocks in built Info.plists ──"
# Xcode has been observed to drop/rewrite the NSExtension block on build.
# Re-assert it directly in the built bundles so registration is reliable.
patch_extension() {
  local plist="$1" point="$2" principal="$3" extra_key="$4" extra_type="$5" extra_val="$6"
  /usr/libexec/PlistBuddy -c "Delete :NSExtension" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy \
    -c "Add :NSExtension dict" \
    -c "Add :NSExtension:NSExtensionPointIdentifier string $point" \
    -c "Add :NSExtension:NSExtensionPrincipalClass string $principal" \
    -c "Add :NSExtension:NSExtensionAttributes dict" \
    -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes array" \
    -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:0 string com.adobe.encapsulated-postscript" \
    -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:1 string com.adobe.postscript" \
    -c "Add :NSExtension:NSExtensionAttributes:$extra_key $extra_type $extra_val" \
    "$plist"
  echo "  patched $(basename "$(dirname "$(dirname "$plist")")")"
}
patch_extension \
  "$APP/Contents/PlugIns/EPSQuickLook.appex/Contents/Info.plist" \
  "com.apple.quicklook.preview" "EPSQuickLook.PreviewViewController" \
  "QLSupportsSearchableItems" "bool" "false"
patch_extension \
  "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Info.plist" \
  "com.apple.quicklook.thumbnail" "EPSThumbnail.ThumbnailProvider" \
  "QLThumbnailMinimumSize" "integer" "16"

echo
echo "── (3.6/5) Stamping build version ──"
# Give every rebuild a unique, monotonically increasing CFBundleVersion so
# LaunchServices / PluginKit never serve cached *old* extension code after
# a reinstall.
BUILD_VERSION="$(date +%Y%m%d%H%M%S)"
for plist in \
  "$APP/Contents/Info.plist" \
  "$APP/Contents/PlugIns/EPSQuickLook.appex/Contents/Info.plist" \
  "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/Info.plist" \
  "$APP/Contents/XPCServices/RenderService.xpc/Contents/Info.plist" \
  "$APP/Contents/PlugIns/EPSQuickLook.appex/Contents/XPCServices/RenderService.xpc/Contents/Info.plist" \
  "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/XPCServices/RenderService.xpc/Contents/Info.plist"; do
  [ -f "$plist" ] || continue
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_VERSION" "$plist"
done
echo "  CFBundleVersion = $BUILD_VERSION"

echo
echo "── (4/5) Ad-hoc signing (inside-out) ──"
sign() { codesign --force --sign - --timestamp=none "$@"; }

# 1. The unsandboxed render service copies (no entitlements → unsandboxed).
sign "$APP/Contents/PlugIns/EPSQuickLook.appex/Contents/XPCServices/RenderService.xpc"
sign "$APP/Contents/PlugIns/EPSThumbnail.appex/Contents/XPCServices/RenderService.xpc"
sign "$APP/Contents/XPCServices/RenderService.xpc"
echo "  signed 3× RenderService.xpc (unsandboxed)"

# 2. The sandboxed extensions, each with its entitlements.
sign --entitlements Sources/QuickLook/QuickLook.entitlements \
  "$APP/Contents/PlugIns/EPSQuickLook.appex"
echo "  signed EPSQuickLook.appex (sandboxed)"
sign --entitlements Sources/Thumbnail/Thumbnail.entitlements \
  "$APP/Contents/PlugIns/EPSThumbnail.appex"
echo "  signed EPSThumbnail.appex (sandboxed)"

# 3. The host app, sealing everything.
sign --entitlements Sources/Host/Host.entitlements "$APP"
echo "  signed EPSPreview.app"

echo
echo "── (5/5) Verifying signature graph ──"
codesign --verify --deep --strict --verbose=2 "$APP" && echo "  ✓ valid"

echo
echo "✓ Build complete: $APP"
echo "  Install with: bash scripts/install.sh"
