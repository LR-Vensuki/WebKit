#!/bin/bash
# Installs the AquaWebKit build in this disk image onto OS X 10.9, for Safari 7 or Safari 9.1.3.
# Everything it replaces is copied first to ~/AquaWebKit-backup; "Restore Stock WebKit.command" puts it back.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" != 0 ]; then
    echo "AquaWebKit writes to /System, so it asks for your administrator password."
    exec sudo /bin/bash "$0" "$@"
fi

case "$(sw_vers -productVersion)" in
    10.9|10.9.*) ;;
    *) echo "ERROR: AquaWebKit is for OS X 10.9; this Mac runs $(sw_vers -productVersion)." >&2; exit 1;;
esac

USER_HOME="$(eval echo "~${SUDO_USER:-root}")"
export STOCK_BACKUP="$USER_HOME/AquaWebKit-backup"
ORIGINAL="$STOCK_BACKUP/replaced-original"
# The installer reads Mach-O files with the cctools shipped beside it: without the Command Line Tools,
# /usr/bin/otool and /usr/bin/strings only offer to install them.
CCTOOLS_BIN="$HERE/payload/AquaWebKitSupport/toolchain/build/cctools/bin"
export PATH="$CCTOOLS_BIN:$PATH"
WEBKIT2=/System/Library/PrivateFrameworks/WebKit2.framework/Versions/A/WebKit2
WEBCLIP="/Library/Widgets/Web Clip.wdgt"
SAVE="/System/Library/Frameworks/JavaScriptCore.framework
/System/Library/Frameworks/WebKit.framework
/System/Library/PrivateFrameworks/WebKit2.framework
$WEBCLIP"

# The major of the current_version an image records: 537 for 10.9's own WebKit, 6xx for this port.
dylib_major() {
    local cmds
    cmds="$("$CCTOOLS_BIN/otool" -arch x86_64 -l "$1" 2>/dev/null)" || return 0
    echo "$cmds" | awk '/cmd LC_ID_DYLIB/ {id = 1} id && /current version/ {split($3, v, "."); print v[1]; exit}'
}

# The backup stays root's: Restore copies it back into /System as root, so nobody else may write to it.
# Earlier versions of this installer handed the backup to the user, so take all of it back.
mkdir -p "$ORIGINAL"
chown -R root:wheel "$STOCK_BACKUP"
chmod 700 "$STOCK_BACKUP"

# Save everything install.sh replaces before it replaces anything. Each copy lands under a scratch
# name and is renamed into place only once complete, so a copy cut short never passes for a backup.
# Only 10.9's own WebKit is worth saving: with this port already installed and no backup left, the
# copy would be the port itself, and Restore would put the port back.
while IFS= read -r item; do
    [ -e "$item" ] || continue
    dest="$ORIGINAL$item"
    [ -e "$dest" ] && continue
    major="$(dylib_major "$WEBKIT2")"
    if [ -z "$major" ] || [ "$major" -ge 600 ]; then
        echo "ERROR: $item is not 10.9's own WebKit (WebKit2 version ${major:-unknown}) and has no backup in" >&2
        echo "       $ORIGINAL. Put the stock frameworks back first (the 10.9.5 combo update reinstalls them)." >&2
        exit 1
    fi
    mkdir -p "$(dirname "$dest")"
    rm -rf "$dest.incoming"
    cp -Rp "$item" "$dest.incoming"
    mv "$dest.incoming" "$dest"
    echo "  saved $item"
done <<< "$SAVE"

bash "$HERE/payload/AquaWebKitSupport/install.sh"
echo
echo "Installed. Restart the Mac so every app loads the new WebKit."
echo "The replaced files are in $STOCK_BACKUP (readable only by an administrator)."
