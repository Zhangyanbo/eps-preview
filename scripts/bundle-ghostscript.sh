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

# Pinned Ghostscript release. `brew install ghostscript` always tracks
# whatever Homebrew currently has on tap, which silently changes the exact
# interpreter binary — and its CVE exposure — shipped in every future build.
# Bump this deliberately (after checking the Ghostscript changelog/CVEs) when
# upgrading, rather than picking up new versions unreviewed.
EXPECTED_GHOSTSCRIPT_VERSION="10.07.1"

OUT="${1:?usage: bundle-ghostscript.sh <output-dir>}"

command -v brew >/dev/null 2>&1 || { echo "error: Homebrew is required to source Ghostscript."; exit 1; }
if ! brew list ghostscript >/dev/null 2>&1; then
  AVAILABLE_VERSION="$(brew info --json=v2 ghostscript 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["formulae"][0]["versions"]["stable"])' 2>/dev/null || echo unknown)"
  if [ "$AVAILABLE_VERSION" != "$EXPECTED_GHOSTSCRIPT_VERSION" ] && [ "${ALLOW_GHOSTSCRIPT_VERSION_MISMATCH:-0}" != "1" ]; then
    echo "error: Homebrew would install Ghostscript $AVAILABLE_VERSION, this script is pinned to $EXPECTED_GHOSTSCRIPT_VERSION."
    echo "       Review the Ghostscript changelog/CVEs for the new version, then either:"
    echo "         - update EXPECTED_GHOSTSCRIPT_VERSION in this script to $AVAILABLE_VERSION, or"
    echo "         - pin Homebrew to the expected version."
    echo "       To install anyway (not recommended), re-run with ALLOW_GHOSTSCRIPT_VERSION_MISMATCH=1."
    exit 1
  fi
  brew install ghostscript
fi

realpath_py() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
GS_BIN="$(realpath_py "$(brew --prefix ghostscript)/bin/gs")"
PREFIX="$(brew --prefix)"
[ -x "$GS_BIN" ] || { echo "error: gs not found at $GS_BIN"; exit 1; }

INSTALLED_VERSION="$("$GS_BIN" --version)"
if [ "$INSTALLED_VERSION" != "$EXPECTED_GHOSTSCRIPT_VERSION" ]; then
  if [ "${ALLOW_GHOSTSCRIPT_VERSION_MISMATCH:-0}" != "1" ]; then
    echo "error: Homebrew has Ghostscript $INSTALLED_VERSION, this script is pinned to $EXPECTED_GHOSTSCRIPT_VERSION."
    echo "       Review the Ghostscript changelog/CVEs for the new version, then either:"
    echo "         - update EXPECTED_GHOSTSCRIPT_VERSION in this script to $INSTALLED_VERSION, or"
    echo "         - pin Homebrew to the expected version."
    echo "       To bundle anyway (not recommended), re-run with ALLOW_GHOSTSCRIPT_VERSION_MISMATCH=1."
    exit 1
  fi
  echo "warning: bundling unpinned Ghostscript $INSTALLED_VERSION (expected $EXPECTED_GHOSTSCRIPT_VERSION)"
fi

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

echo "→ recording provenance…"
{
  echo "version=$INSTALLED_VERSION"
  echo "converter_sha256=$(shasum -a 256 "$OUT/converter" | awk '{print $1}')"
  for dy in "$OUT"/lib/*.dylib; do
    [ -f "$dy" ] || continue
    echo "lib_sha256=$(basename "$dy") $(shasum -a 256 "$dy" | awk '{print $1}')"
  done
  echo "bundled_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/GHOSTSCRIPT_PROVENANCE.txt"

echo "✓ self-contained Ghostscript at $OUT ($(du -sh "$OUT" | cut -f1))"
