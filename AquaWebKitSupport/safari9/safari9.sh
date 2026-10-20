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

# The dylibs an image loads, one path per line. Fails, rather than printing nothing, when otool
# cannot read the image, so no caller mistakes an unreadable binary for an already-patched one.
dylib_loads() {
    local out
    out="$("$OTOOL" -arch x86_64 -L "$1")" || { echo "ERROR: otool could not read $1" >&2; return 1; }
    echo "$out" | awk 'NR > 1 {print $1}'
}

# True when the image $1 loads the legacy WebKit, i.e. Safari.framework as Apple shipped it. The load
# list is captured first: grep -q on a pipe can end the writer early, which pipefail reports as failure.
binds_legacy_webkit() {
    local loads
    loads="$(dylib_loads "$1")" || exit 1
    case "$(printf '\n%s\n' "$loads")" in
        *"
$LEGACY_WEBKIT
"*) return 0 ;;
    esac
    return 1
}

# True when the image $1 carries a code signature (LC_CODE_SIGNATURE).
has_code_signature() {
    local cmds
    cmds="$("$OTOOL" -arch x86_64 -l "$1")" || { echo "ERROR: otool could not read $1" >&2; exit 1; }
    case "$cmds" in *LC_CODE_SIGNATURE*) return 0 ;; esac
    return 1
}

# Moves the patched copy $1 of Safari.framework's binary into place without its code signature. The
# patch voids Apple's signature, and the kernel kills a process that maps a page whose signature no
# longer matches; 10.9 loads unsigned frameworks. An ad-hoc signature is no option: codesign only
# runs an Apple-signed codesign_allocate, which a Mac without the Command Line Tools lacks. The copy
# is renamed over the binary, so a running Safari keeps the image it mapped. Nested code (the
# SocialHelper service) keeps its own signature; the bundle's seal goes with the binary's.
replace_unsigned() {
    rm -f "$1.unsigned"
    "$CCTOOLS/codesign_allocate" -i "$1" -r -o "$1.unsigned"
    rm -f "$1"
    chown root:wheel "$1.unsigned"
    chmod 755 "$1.unsigned"
    mv -f "$1.unsigned" "$SAFARI9_BINARY"
    rm -rf "$SAFARI9_SIGNATURE"
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
    if binds_legacy_webkit "$SAFARI9_BINARY"; then
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
    chmod 700 "$SAFARI9_BACKUP"
    if binds_legacy_webkit "$SAFARI9_BINARY"; then
        # The binary is Apple's as shipped -- also after Safari 9 was reinstalled over an earlier
        # patch -- so it is the one to keep. It is taken with its signature in a scratch folder and
        # moved into place only once complete, so an interrupted copy never stands as the backup.
        if ! cmp -s "$SAFARI9_BINARY" "$SAFARI9_BACKUP/Safari"; then
            rm -rf "$SAFARI9_BACKUP/.incoming"
            mkdir "$SAFARI9_BACKUP/.incoming"
            cp -p "$SAFARI9_BINARY" "$SAFARI9_BACKUP/.incoming/Safari"
            [ -d "$SAFARI9_SIGNATURE" ] && cp -Rp "$SAFARI9_SIGNATURE" "$SAFARI9_BACKUP/.incoming/_CodeSignature"
            rm -rf "$SAFARI9_BACKUP/Safari" "$SAFARI9_BACKUP/_CodeSignature"
            [ -d "$SAFARI9_BACKUP/.incoming/_CodeSignature" ] && mv "$SAFARI9_BACKUP/.incoming/_CodeSignature" "$SAFARI9_BACKUP/"
            mv "$SAFARI9_BACKUP/.incoming/Safari" "$SAFARI9_BACKUP/Safari"
            rmdir "$SAFARI9_BACKUP/.incoming"
            echo "  backed up $SAFARI9_BINARY -> $SAFARI9_BACKUP"
        fi
        rm -f "$SAFARI9_BINARY.patching"
        cp -p "$SAFARI9_BINARY" "$SAFARI9_BINARY.patching"
        "$INSTALL_NAME_TOOL" -change "$LEGACY_WEBKIT" "$MODERN_WEBKIT" "$SAFARI9_BINARY.patching"
        replace_unsigned "$SAFARI9_BINARY.patching"
        echo "  Safari.framework now binds its WebKit symbols from $MODERN_WEBKIT"
    else
        echo "  Safari.framework already binds its WebKit symbols from $MODERN_WEBKIT"
        # Earlier versions of this script left the patched binary with a signature that no longer
        # matched it, and the kernel kills Safari on the first page it checks against it.
        if has_code_signature "$SAFARI9_BINARY"; then
            rm -f "$SAFARI9_BINARY.patching"
            cp -p "$SAFARI9_BINARY" "$SAFARI9_BINARY.patching"
            replace_unsigned "$SAFARI9_BINARY.patching"
            echo "  took the stale signature off $SAFARI9_BINARY"
        fi
    fi
    if binds_legacy_webkit "$SAFARI9_BINARY"; then
        echo "ERROR: $SAFARI9_BINARY still loads $LEGACY_WEBKIT." >&2
        exit 1
    fi

    if [ -d "$STAGED_INSPECTOR_UI" ] && staged_framework_wins "$STAGED_INSPECTOR_UI/Versions/A/WebInspectorUI"; then
        # The staged copy is Apple's (a newer one if Safari 9 was reinstalled): it replaces any older backup.
        rm -rf "$SAFARI9_BACKUP/WebInspectorUI.framework.old"
        [ -d "$SAFARI9_BACKUP/WebInspectorUI.framework" ] && mv "$SAFARI9_BACKUP/WebInspectorUI.framework" "$SAFARI9_BACKUP/WebInspectorUI.framework.old"
        mv "$STAGED_INSPECTOR_UI" "$SAFARI9_BACKUP/WebInspectorUI.framework"
        rm -rf "$SAFARI9_BACKUP/WebInspectorUI.framework.old"
        echo "  set the staged WebInspectorUI aside, so Safari 9 uses $SYSTEM_INSPECTOR_UI"
    fi
    echo "  done. Quit Safari before launching it again."
}

restore() {
    [ "$(id -u)" = 0 ] || { echo "ERROR: this writes to /System -- run it as root: sudo bash $0 restore" >&2; exit 1; }
    [ -d "$SAFARI9_BACKUP" ] || { echo "No backup at $SAFARI9_BACKUP; nothing to restore."; return 0; }
    if [ -f "$SAFARI9_BACKUP/Safari" ] && [ -d "$SAFARI9_BUNDLE" ]; then
        # Into a new file renamed over the old one, so a running Safari keeps the image it mapped.
        cp -p "$SAFARI9_BACKUP/Safari" "$SAFARI9_BINARY.restoring"
        mv -f "$SAFARI9_BINARY.restoring" "$SAFARI9_BINARY"
        if [ -d "$SAFARI9_BACKUP/_CodeSignature" ]; then
            rm -rf "$SAFARI9_SIGNATURE"
            cp -Rp "$SAFARI9_BACKUP/_CodeSignature" "$SAFARI9_SIGNATURE"
        fi
        chown root:wheel "$SAFARI9_BINARY"
        [ -d "$SAFARI9_SIGNATURE" ] && chown -R root:wheel "$SAFARI9_SIGNATURE"
        rm -rf "$SAFARI9_BACKUP/Safari" "$SAFARI9_BACKUP/_CodeSignature"
        echo "  restored $SAFARI9_BINARY"
    fi
    if [ -d "$SAFARI9_BACKUP/WebInspectorUI.framework" ] && [ -d "$STAGED" ]; then
        rm -rf "$STAGED_INSPECTOR_UI"
        mv "$SAFARI9_BACKUP/WebInspectorUI.framework" "$STAGED_INSPECTOR_UI"
        chown -R root:wheel "$STAGED_INSPECTOR_UI"
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
