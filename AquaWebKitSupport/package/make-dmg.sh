#!/bin/bash
# make-dmg.sh — wrap the staged product (WebKitBuild/Release/staged) in a disk image that installs on a
# 10.9 Mac with no checkout and no developer tools: the staged tree, install.sh and the scripts it sources,
# safari9.sh, and the cctools they read Mach-O files with, laid out as in the repo so framework-layout.sh
# finds everything relative to itself. Run on the build host after build.sh: bash make-dmg.sh [out.dmg]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STAGED="$REPO/WebKitBuild/Release/staged"
OUT="${1:-$REPO/WebKitBuild/AquaWebKit.dmg}"

[ -f "$STAGED/.build-complete" ] || { echo "ERROR: no complete staged product; run build.sh first." >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aquawebkit-dmg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/AquaWebKit"
P="$ROOT/payload"
mkdir -p "$P/AquaWebKitSupport/scripts" "$P/AquaWebKitSupport/safari9" \
         "$P/AquaWebKitSupport/toolchain/build/cctools" "$P/WebKitBuild/Release"

cp -p "$REPO/AquaWebKitSupport/install.sh" "$P/AquaWebKitSupport/"
cp -p "$REPO/AquaWebKitSupport/scripts/framework-layout.sh" "$REPO/AquaWebKitSupport/scripts/cctools.sh" \
      "$P/AquaWebKitSupport/scripts/"
cp -p "$REPO/AquaWebKitSupport/safari9/safari9.sh" "$P/AquaWebKitSupport/safari9/"
cp -Rp "$REPO/AquaWebKitSupport/toolchain/build/cctools/bin" "$P/AquaWebKitSupport/toolchain/build/cctools/"
cp -Rp "$STAGED" "$P/WebKitBuild/Release/staged"

cp -p "$HERE/Install AquaWebKit.command" "$HERE/Restore Stock WebKit.command" "$HERE/README.txt" "$ROOT/"
cp -p "$REPO/AquaWebKitSupport/docs/SAFARI-9.md" "$ROOT/VALIDATION.txt"
chmod +x "$ROOT/"*.command
{
    echo "Revision: $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "Branch:   $(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "Built:    $(cat "$STAGED/.build-complete")"
} > "$ROOT/BUILD-INFO.txt"

rm -f "$OUT"
hdiutil create -quiet -volname AquaWebKit -srcfolder "$ROOT" -format UDZO -imagekey zlib-level=9 "$OUT"
echo "$OUT ($(du -h "$OUT" | cut -f1))"
