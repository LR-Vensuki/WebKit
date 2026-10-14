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
# The installer reads Mach-O files with the cctools shipped beside it: without the Command Line Tools,
# /usr/bin/otool and /usr/bin/strings only offer to install them.
export PATH="$HERE/payload/AquaWebKitSupport/toolchain/build/cctools/bin:$PATH"

# install.sh preserves the three framework bundles itself; the Web Clip widget it also edits is kept here.
WEBCLIP="/Library/Widgets/Web Clip.wdgt"
if [ -d "$WEBCLIP" ] && [ ! -d "$STOCK_BACKUP/replaced-original$WEBCLIP" ]; then
    mkdir -p "$STOCK_BACKUP/replaced-original/Library/Widgets"
    cp -Rp "$WEBCLIP" "$STOCK_BACKUP/replaced-original/Library/Widgets/"
fi

bash "$HERE/payload/AquaWebKitSupport/install.sh"
chown -R "${SUDO_USER:-root}" "$STOCK_BACKUP" 2>/dev/null || true
echo
echo "Installed. Restart the Mac so every app loads the new WebKit."
echo "The replaced files are in $STOCK_BACKUP."
