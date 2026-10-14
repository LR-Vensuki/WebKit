#!/bin/bash
# Puts back the WebKit that "Install AquaWebKit.command" replaced, from ~/AquaWebKit-backup.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" != 0 ]; then
    echo "Restoring writes to /System, so it asks for your administrator password."
    exec sudo /bin/bash "$0" "$@"
fi

USER_HOME="$(eval echo "~${SUDO_USER:-root}")"
export STOCK_BACKUP="$USER_HOME/AquaWebKit-backup"
export PATH="$HERE/payload/AquaWebKitSupport/toolchain/build/cctools/bin:$PATH"
ORIGINAL="$STOCK_BACKUP/replaced-original"
BUNDLES="/System/Library/Frameworks/JavaScriptCore.framework
/System/Library/Frameworks/WebKit.framework
/System/Library/PrivateFrameworks/WebKit2.framework"

# Check every copy before touching anything, so a missing one cannot leave /System half restored.
echo "$BUNDLES" | while read -r bundle; do
    [ -d "$ORIGINAL$bundle" ] || { echo "ERROR: no saved copy of $bundle in $ORIGINAL." >&2; exit 1; }
done

if [ -d "$STOCK_BACKUP/safari9" ]; then
    bash "$HERE/payload/AquaWebKitSupport/safari9/safari9.sh" restore
fi

echo "$BUNDLES" | while read -r bundle; do
    echo "== $bundle"
    rm -rf "$bundle"
    cp -Rp "$ORIGINAL$bundle" "$bundle"
    chown -R root:wheel "$bundle"
done

WEBCLIP="/Library/Widgets/Web Clip.wdgt"
if [ -d "$ORIGINAL$WEBCLIP" ]; then
    rm -rf "$WEBCLIP"
    cp -Rp "$ORIGINAL$WEBCLIP" "$WEBCLIP"
    chown -R root:admin "$WEBCLIP"
fi

/usr/libexec/xpchelper --rebuild-cache
echo
echo "Restored. Restart the Mac. You can delete $STOCK_BACKUP after that."
