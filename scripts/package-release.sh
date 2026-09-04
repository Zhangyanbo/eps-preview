#!/usr/bin/env bash
# Build a self-contained, drag-to-install release:
#   - builds EPSPreview.app
#   - embeds a self-contained Ghostscript (no Homebrew needed at runtime)
#   - re-signs (ad-hoc) and produces dist/EPSPreview-<version>.dmg
#
# The .dmg is ad-hoc signed (no Apple Developer Program), so first launch
# still needs the user to approve it once in System Settings → Privacy &
# Security. See the bundled 安装说明 / INSTALL file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${1:-1.0.0}"

APP="build/Build/Products/Release/EPSPreview.app"
LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

echo "════ 1/4  Build app ════"
bash scripts/build.sh

echo
echo "════ 2/4  Embed self-contained Ghostscript ════"
GSTMP="$(mktemp -d)/gs"
bash scripts/bundle-ghostscript.sh "$GSTMP"
# Split: Mach-O (binary + libs) into Helpers/, the resource tree into
# Resources/. codesign refuses to seal a big loose data tree that sits in the
# same folder as Mach-O binaries, so they must live apart.
mkdir -p "$APP/Contents/Helpers/gs" "$APP/Contents/Resources/ghostscript"
cp -f "$GSTMP/converter" "$APP/Contents/Helpers/gs/converter"
cp -R "$GSTMP/lib" "$APP/Contents/Helpers/gs/lib"
cp -R "$GSTMP/share/." "$APP/Contents/Resources/ghostscript/"
# Carry the provenance record (gs version + binary hashes) into the shipped
# app, before the re-seal below so it is covered by the signature.
cp -f "$GSTMP/GHOSTSCRIPT_PROVENANCE.txt" "$APP/Contents/Resources/ghostscript/GHOSTSCRIPT_PROVENANCE.txt"
rm -rf "$(dirname "$GSTMP")"

echo
echo "════ 3/4  Re-seal the app (added Contents/Helpers) ════"
# Adding Helpers/ invalidated the app's outer seal; re-sign the host app so
# the bundled gs is covered. (Nested extensions/service stay as signed.)
codesign --force --sign - --timestamp=none \
  --entitlements Sources/Host/Host.entitlements "$APP"
codesign --verify --deep --strict "$APP" && echo "  ✓ signature valid"

echo
echo "════ 4/4  Build DMG ════"
STAGE="$(mktemp -d)/EPS Preview"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/EPSPreview.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明 INSTALL.txt" <<'EOF'
EPS Preview — 安装步骤 / How to install
=======================================

中文
----
1. 把 EPSPreview.app 拖到旁边的「Applications」文件夹。
2. 打开「访达 → 应用程序」，找到 EPSPreview，双击打开。
3. 第一次会被系统拦截（因为没有花钱做 Apple 公证）。这时打开
   「系统设置 → 隐私与安全性」，往下拉，点「仍要打开 / Open Anyway」，
   再确认一次即可。以后就不会再提示。
4. 打开一次 App 后，在访达里选中任意 .eps / .ps 文件，按【空格】预览，
   文件图标也会显示缩略图。

不需要安装 Homebrew 或 Ghostscript —— 都已打包在 App 内。

English
-------
1. Drag EPSPreview.app onto the "Applications" folder shown here.
2. In Applications, double-click EPSPreview.
3. macOS will block it the first time (the app is not Apple-notarized).
   Open System Settings → Privacy & Security, scroll down, click
   "Open Anyway", and confirm. You only do this once.
4. After launching it once, select any .eps / .ps file in Finder and press
   Space to preview; Finder icons will show thumbnails too.

No Homebrew or Ghostscript install needed — both are bundled inside the app.
EOF

mkdir -p dist
DMG="dist/EPSPreview-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "EPS Preview" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")"

echo
echo "✓ Release built: $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
