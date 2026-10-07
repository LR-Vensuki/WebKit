#!/bin/bash
# safari9.sh — run stock Safari 9.1.3 for 10.9 (9537.86.7.8, the last Safari for Mavericks) on this port,
# alongside the Safari 7.0.6 the port is built around. See docs/SAFARI-9.md.
#
# Safari 9 for 10.9 is the Safari 7 application built against WebKit 601. Its installer stages that
# WebKit under /System/Library/StagedFrameworks/Safari, and Safari.app, Safari's XPC services and
# 601's own services reach it through an LC_DYLD_ENVIRONMENT DYLD_VERSIONED_FRAMEWORK_PATH. dyld takes
# a staged framework only when it is newer than the image at that framework's install name, and this
# port's frameworks carry WEBKIT_MAC_VERSION (625.x), so Safari 9 already loads this port's
# JavaScriptCore, WebKit, WebKit2 and WebCore; only its own Safari.framework (537.86.7, newer than
# 10.9's 537.78) comes from the staged directory. Two things still separate it from a working browser:
#
#  1. Where its WebKit binds resolve. Safari.framework binds all 627 WebKit symbols it uses from
#     /System/Library/Frameworks/WebKit.framework, because in 601 that framework is the WK2 one and
#     re-exports WebKitLegacy. In this port's 10.9 layout WebKit.framework is WebKitLegacy, and WK2 is
#     WebKit2.framework, which re-exports WebKitLegacy. Repointing that one load command at WebKit2
#     makes every bind resolve, the WK1 ones through the re-export, with no new image and no
#     re-export cycle. The same binary is the WebProcess plug-in Safari loads into this port's
#     WebContent processes (it passes [NSBundle bundleWithIdentifier:@"com.apple.Safari.framework"]'s
#     path), so this covers both sides. host-abi/safari9-needs-from-WebKit2.txt is the contract the
#     build holds WebKit2 to.
#  2. The inspector frontend. The staged WebInspectorUI 601 outranks 10.9's in Safari's process, but
#     this port drives 10.9's classic frontend through the bridge in
#     source/WebCore/inspector/InspectorFrontendClassicBridge.h, written against 10.9's frontend.
#     When the staged one would win, it is set aside so Safari 9 gets the frontend the bridge knows.
#
# Every file changed is backed up once under $SAFARI9_BACKUP; `restore` puts Safari 9 back as Apple
# shipped it. The rest of the staged 601 engine is left in place: it is unused while this port is
# installed, and it is what Safari 9 runs on again if the stock frameworks are restored.
#
# Usage: sudo bash safari9.sh install | restore      bash safari9.sh status
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/framework-layout.sh"

STAGED=/System/Library/StagedFrameworks/Safari
SAFARI9_BUNDLE=$STAGED/Safari.framework
SAFARI9_BINARY=$SAFARI9_BUNDLE/Versions/A/Safari
SAFARI9_SIGNATURE=$SAFARI9_BUNDLE/Versions/A/_CodeSignature
LEGACY_WEBKIT=$WEBKIT_BUNDLE/Versions/A/WebKit
MODERN_WEBKIT=$WEBKIT2_BUNDLE/Versions/A/WebKit2
STAGED_INSPECTOR_UI=$STAGED/WebInspectorUI.framework
SYSTEM_INSPECTOR_UI=$PRIVATE_DIR/WebInspectorUI.framework
SAFARI9_BACKUP="${SAFARI9_BACKUP:-$STOCK_BACKUP/safari9}"

# The current_version an image's LC_ID_DYLIB records ("" when there is none).
dylib_version() {
    [ -f "$1" ] || return 0
    "$OTOOL" -arch x86_64 -l "$1" 2>/dev/null | awk '/cmd LC_ID_DYLIB/ {id = 1} id && /current version/ {print $3; exit}'
}

# A dotted dylib version as the 32-bit number dyld compares (xxxx.yy.zz).
packed_version() {
    echo "${1:-0}" | awk -F. '{print ($1 + 0) * 65536 + ($2 + 0) * 256 + ($3 + 0)}'
}

# The dylibs an image loads, one path per line.
dylib_loads() {
    "$OTOOL" -arch x86_64 -L "$1" | awk 'NR > 1 {print $1}'
}

safari9_present() {
    [ -f "$SAFARI9_BINARY" ]
}

safari9_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SAFARI9_BUNDLE/Versions/A/Resources/Info.plist" 2>/dev/null || echo unknown
}

# True when dyld, searching $STAGED for Safari's processes, takes the staged copy of the framework
# whose binary is $1 over the image at its install name.
staged_framework_wins() {
    local staged="$1" installName
    installName="$("$OTOOL" -arch x86_64 -D "$staged" 2>/dev/null | awk 'NR == 2')"
    [ -n "$installName" ] || return 1
    [ "$(packed_version "$(dylib_version "$staged")")" -gt "$(packed_version "$(dylib_version "$installName")")" ]
}

status() {
    if ! safari9_present; then
        echo "Safari 9 is not installed ($SAFARI9_BINARY is absent)."
        return 0
    fi
    echo "Safari 9 staged framework: $(safari9_version)"
    if dylib_loads "$SAFARI9_BINARY" | grep -qx "$LEGACY_WEBKIT"; then
        echo "  WebKit binds: from $LEGACY_WEBKIT (as Apple shipped it; run install)"
    else
        echo "  WebKit binds: from $MODERN_WEBKIT"
    fi
    local fw binary
    for fw in JavaScriptCore WebKit WebKit2 WebCore WebInspectorUI; do
        binary="$STAGED/$fw.framework/Versions/A/$fw"
        [ -f "$binary" ] || { echo "  staged $fw: absent"; continue; }
        if staged_framework_wins "$binary"; then
            echo "  staged $fw $(dylib_version "$binary"): wins over the installed one"
        else
            echo "  staged $fw $(dylib_version "$binary"): unused (the installed one is newer)"
        fi
    done
    [ -d "$SAFARI9_BACKUP" ] && echo "  backup: $SAFARI9_BACKUP"
    return 0
}

install() {
    safari9_present || { echo "Safari 9 is not installed; nothing to do."; return 0; }
    [ "$(id -u)" = 0 ] || { echo "ERROR: this writes to /System -- run it as root: sudo bash $0 install" >&2; exit 1; }
    [ -f "$MODERN_WEBKIT" ] || { echo "ERROR: this port is not installed ($MODERN_WEBKIT is absent)." >&2; exit 1; }

    # Safari 9 reaches this port only while every staged engine framework is older than this port's.
    local fw binary
    for fw in JavaScriptCore WebKit WebKit2 WebCore; do
        binary="$STAGED/$fw.framework/Versions/A/$fw"
        if [ -f "$binary" ] && staged_framework_wins "$binary"; then
            echo "ERROR: the staged $fw ($(dylib_version "$binary")) outranks the installed one, so Safari 9" >&2
            echo "       would run on its own engine. Install this port's frameworks first." >&2
            exit 1
        fi
    done

    echo "### Safari 9 ($(safari9_version)) on this port"
    mkdir -p "$SAFARI9_BACKUP"
    if dylib_loads "$SAFARI9_BINARY" | grep -qx "$LEGACY_WEBKIT"; then
        if [ ! -f "$SAFARI9_BACKUP/Safari" ]; then
            cp -p "$SAFARI9_BINARY" "$SAFARI9_BACKUP/Safari"
            rm -rf "$SAFARI9_BACKUP/_CodeSignature"
            [ -d "$SAFARI9_SIGNATURE" ] && cp -Rp "$SAFARI9_SIGNATURE" "$SAFARI9_BACKUP/_CodeSignature"
            echo "  backed up $SAFARI9_BINARY -> $SAFARI9_BACKUP"
        fi
        "$INSTALL_NAME_TOOL" -change "$LEGACY_WEBKIT" "$MODERN_WEBKIT" "$SAFARI9_BINARY"
        # The edit voids Apple's signature over the load commands; an ad-hoc one keeps the bundle
        # self-consistent. Nested code (the SocialHelper service) keeps its own signature.
        codesign -f -s - "$SAFARI9_BUNDLE" 2>/dev/null || echo "  (could not re-sign $SAFARI9_BUNDLE ad hoc; it loads unsigned)"
        echo "  Safari.framework now binds its WebKit symbols from $MODERN_WEBKIT"
    else
        echo "  Safari.framework already binds its WebKit symbols from $MODERN_WEBKIT"
    fi
    if dylib_loads "$SAFARI9_BINARY" | grep -qx "$LEGACY_WEBKIT"; then
        echo "ERROR: $SAFARI9_BINARY still loads $LEGACY_WEBKIT." >&2
        exit 1
    fi

    if [ -d "$STAGED_INSPECTOR_UI" ] && staged_framework_wins "$STAGED_INSPECTOR_UI/Versions/A/WebInspectorUI"; then
        rm -rf "$SAFARI9_BACKUP/WebInspectorUI.framework"
        mv "$STAGED_INSPECTOR_UI" "$SAFARI9_BACKUP/WebInspectorUI.framework"
        echo "  set the staged WebInspectorUI aside, so Safari 9 uses $SYSTEM_INSPECTOR_UI"
    fi
    echo "  done. Quit Safari before launching it again."
}

restore() {
    [ "$(id -u)" = 0 ] || { echo "ERROR: this writes to /System -- run it as root: sudo bash $0 restore" >&2; exit 1; }
    [ -d "$SAFARI9_BACKUP" ] || { echo "No backup at $SAFARI9_BACKUP; nothing to restore."; return 0; }
    if [ -f "$SAFARI9_BACKUP/Safari" ] && [ -d "$SAFARI9_BUNDLE" ]; then
        cp -p "$SAFARI9_BACKUP/Safari" "$SAFARI9_BINARY"
        if [ -d "$SAFARI9_BACKUP/_CodeSignature" ]; then
            rm -rf "$SAFARI9_SIGNATURE"
            cp -Rp "$SAFARI9_BACKUP/_CodeSignature" "$SAFARI9_SIGNATURE"
        fi
        rm -rf "$SAFARI9_BACKUP/Safari" "$SAFARI9_BACKUP/_CodeSignature"
        echo "  restored $SAFARI9_BINARY"
    fi
    if [ -d "$SAFARI9_BACKUP/WebInspectorUI.framework" ]; then
        rm -rf "$STAGED_INSPECTOR_UI"
        mv "$SAFARI9_BACKUP/WebInspectorUI.framework" "$STAGED_INSPECTOR_UI"
        echo "  restored $STAGED_INSPECTOR_UI"
    fi
    rmdir "$SAFARI9_BACKUP" 2>/dev/null || true
}

case "${1:-status}" in
    install) install ;;
    restore) restore ;;
    status)  status ;;
    *) echo "usage: $0 install | restore | status" >&2; exit 2 ;;
esac
