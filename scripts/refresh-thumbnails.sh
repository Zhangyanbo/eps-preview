#!/usr/bin/env bash
# Force Finder to regenerate EPS thumbnails. Useful for files whose generic
# icon got cached before EPS Preview was installed.
#
# Does NOT modify your files.
set -euo pipefail

echo "Resetting Quick Look thumbnail cache…"
qlmanage -r cache >/dev/null 2>&1 || true

echo "Restarting Finder and thumbnail agents…"
killall Finder                               >/dev/null 2>&1 || true
killall quicklookd                           >/dev/null 2>&1 || true
killall thumbnailservicesagent               >/dev/null 2>&1 || true
killall com.apple.quicklook.ThumbnailsAgent  >/dev/null 2>&1 || true

echo "✓ Done. Open a folder of .eps files in icon view; thumbnails will"
echo "  regenerate as the files come into view (give it a few seconds)."
echo
echo "If a specific file still shows a generic icon, it has an especially"
echo "sticky icon cache — duplicating it (⌘D) forces a fresh thumbnail."
