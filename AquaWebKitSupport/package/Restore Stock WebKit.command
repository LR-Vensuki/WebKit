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
WEBCLIP="/Library/Widgets/Web Clip.wdgt"
BUNDLES="/System/Library/Frameworks/JavaScriptCore.framework
/System/Library/Frameworks/WebKit.framework
/System/Library/PrivateFrameworks/WebKit2.framework"

# Check every copy before touching anything, so a missing one cannot leave /System half restored.
# The loops read from here-strings, not pipes: in bash 3.2 an exit inside a piped loop only ends the
# loop's subshell, and set -e does not catch it.
while IFS= read -r bundle; do
    [ -d "$ORIGINAL$bundle" ] || { echo "ERROR: no saved copy of $bundle in $ORIGINAL; nothing was changed." >&2; exit 1; }
done <<< "$BUNDLES"
if [ -d "$WEBCLIP" ] && [ ! -d "$ORIGINAL$WEBCLIP" ]; then
    echo "ERROR: no saved copy of the Web Clip widget in $ORIGINAL; nothing was changed." >&2
    exit 1
fi

if [ -d "$STOCK_BACKUP/safari9" ]; then
    bash "$HERE/payload/AquaWebKitSupport/safari9/safari9.sh" restore
fi

# Each original is copied beside its target first and swapped in only once the copy is complete.
restore_item() {  # path, owner
    rm -rf "$1.restoring"
    cp -Rp "$ORIGINAL$1" "$1.restoring"
    chown -R "$2" "$1.restoring"
    rm -rf "$1"
    mv "$1.restoring" "$1"
}
while IFS= read -r bundle; do
    echo "== $bundle"
    restore_item "$bundle" root:wheel
done <<< "$BUNDLES"
if [ -d "$ORIGINAL$WEBCLIP" ]; then
    echo "== $WEBCLIP"
    restore_item "$WEBCLIP" root:admin
fi

/usr/libexec/xpchelper --rebuild-cache
echo
echo "Restored. Restart the Mac. You can delete $STOCK_BACKUP after that."
