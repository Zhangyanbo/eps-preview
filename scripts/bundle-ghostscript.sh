#!/usr/bin/env bash
# Build a self-contained Ghostscript tree into <output-dir>:
#
#   converter           the gs executable (dependent libs rewritten to @rpath)
#   lib/*.dylib         every non-system library it transitively needs
#   share/Resource/…    gs init / font / resource files
#   share/lib/…
#
# This lets the app render EPS on machines without Homebrew. It sources
# Homebrew's Ghostscript, which is AGPL-3.0 — the produced binary is AGPL;
# see NOTICE.md.
set -euo pipefail

OUT="${1:?usage: bundle-ghostscript.sh <output-dir>}"

command -v brew >/dev/null 2>&1 || { echo "error: Homebrew is required to source Ghostscript."; exit 1; }
brew list ghostscript >/dev/null 2>&1 || brew install ghostscript

realpath_py() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
GS_BIN="$(realpath_py "$(brew --prefix ghostscript)/bin/gs")"
PREFIX="$(brew --prefix)"
[ -x "$GS_BIN" ] || { echo "error: gs not found at $GS_BIN"; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT/lib"
cp -f "$GS_BIN" "$OUT/converter"; chmod u+w "$OUT/converter"

# Dependent libraries, excluding OS libs and self/relative references.
list_deps() {
  otool -L "$1" 2>/dev/null | tail -n +2 | awk '{print $1}' \
    | grep -vE '^/usr/lib/|^/System/|^@executable_path/|^@loader_path/'
}
resolve_lib() { # basename -> absolute path inside Homebrew
  local b="$1"
  [ -f "$PREFIX/lib/$b" ] && { echo "$PREFIX/lib/$b"; return; }
  find "$PREFIX/Cellar" "$PREFIX/opt" -maxdepth 6 -name "$b" -type f 2>/dev/null | head -1
}

echo "→ collecting dependent libraries…"
changed=1
while [ "$changed" -eq 1 ]; do
  changed=0
  for bin in "$OUT/converter" "$OUT"/lib/*.dylib; do
    [ -f "$bin" ] || continue
    while IFS= read -r dep; do
      [ -n "$dep" ] || continue
      case "$dep" in
        @rpath/*) base="${dep#@rpath/}" ;;
        *)        base="$(basename "$dep")" ;;
      esac
      [ -f "$OUT/lib/$base" ] && continue
      src=""
      [ "${dep:0:1}" = "/" ] && [ -f "$dep" ] && src="$dep"
      [ -n "$src" ] || src="$(resolve_lib "$base")"
      if [ -n "$src" ] && [ -f "$src" ]; then
        cp -f "$src" "$OUT/lib/$base"; chmod u+w "$OUT/lib/$base"; changed=1
        echo "   + $base"
      fi
    done < <(list_deps "$bin")
  done
done

echo "→ rewriting install names to @rpath…"
retarget() {
  local f="$1"
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$f" 2>/dev/null || true
  done < <(list_deps "$f")
}
for dy in "$OUT"/lib/*.dylib; do
  [ -f "$dy" ] || continue
  install_name_tool -id "@rpath/$(basename "$dy")" "$dy" 2>/dev/null || true
  retarget "$dy"
done
retarget "$OUT/converter"
install_name_tool -add_rpath "@executable_path/lib" "$OUT/converter" 2>/dev/null || true

echo "→ copying Ghostscript resources…"
GSSHARE="$(dirname "$(dirname "$GS_BIN")")/share/ghostscript"
[ -d "$GSSHARE/Resource" ] || GSSHARE="$("$GS_BIN" -h 2>/dev/null | grep -m1 'Resource/Init' | sed 's#/Resource/Init.*##' | tr -d ' :')"
mkdir -p "$OUT/share"
cp -R "$GSSHARE/Resource" "$OUT/share/" 2>/dev/null || true
cp -R "$GSSHARE/lib"      "$OUT/share/" 2>/dev/null || true

echo "→ ad-hoc signing…"
for dy in "$OUT"/lib/*.dylib; do codesign --force --sign - "$dy" 2>/dev/null || true; done
codesign --force --sign - "$OUT/converter" 2>/dev/null || true

echo "✓ self-contained Ghostscript at $OUT ($(du -sh "$OUT" | cut -f1))"
