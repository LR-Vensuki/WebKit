# Safari 9 on Aqua WebKit

The port is built around the Safari 7.0.6 that 10.9.5 ships. Safari 9.1.3 (9537.86.7.8), the last Safari
Apple released for Mavericks, runs on it too once `safari9/safari9.sh install` has run; `install.sh` does
that by itself when it finds Safari 9 installed. Nothing has to be downgraded.

## What Safari 9 for 10.9 is

It is the Safari 7 application line (its bundle version is 9537.x, like Safari 7's) built against
**WebKit 601.7.8**, the engine of Safari 9 on 10.10 and 10.11. Its installer (`Safari9.1.3Mavericks.pkg`)
leaves the system frameworks alone and puts the newer ones in `/System/Library/StagedFrameworks/Safari`:
JavaScriptCore, WebCore, WebKit, WebKit2, WebKitLegacy, WebInspector, WebInspectorUI and Safari's own
Safari.framework. Safari.app, Safari's XPC services and 601's WebKit services carry an
`LC_DYLD_ENVIRONMENT` of `DYLD_VERSIONED_FRAMEWORK_PATH=/System/Library/StagedFrameworks/Safari`.

dyld (10.9's) reads that variable once per process: for each `X.framework` in the directory it compares
the staged binary's `current_version` with the image at that binary's install name, and only a newer staged
binary overrides it. This port stamps its frameworks with `WEBKIT_MAC_VERSION` (625.x), so in Safari 9's
processes JavaScriptCore, WebKit, WebKit2 and WebCore already come from this port. Safari.framework
(537.86.7, against 10.9's 537.78) still comes from the staged directory, which is what Safari 9 needs.

## The ABI it binds

`host-abi/safari9-imports.txt` is every symbol the staged Safari.framework imports. Of them, it binds

| From | Symbols | Already in a 10.9 contract |
|---|---|---|
| `/System/Library/Frameworks/WebKit.framework` | 627 | 619 (595 from Safari 7's WebKit2 contract, its 24 WebKit ones) |
| `/System/Library/Frameworks/JavaScriptCore.framework` | 95 | all: they are Safari 7's 95, symbol for symbol |
| `/System/Library/PrivateFrameworks/WebKit2.framework` | 0 | |

The 8 WebKit symbols no 10.9 binary binds:

- `WKPageRunJavaScriptAlertResultListenerCall`, `…ConfirmResultListenerCall`, `…PromptResultListenerCall`
  and `WKPageSetBackgroundExtendsBeyondPage` still exist upstream.
- `WKContextGetOriginDataManager`, `WKOriginDataManagerGetOrigins`, `WKOriginDataManagerDeleteEntriesForOrigin`
  and `WKOriginDataManagerDeleteAllEntries` were folded into `WKWebsiteDataStore` after 601. They are
  restored at the end of `Source/WebKit/UIProcess/API/C/WKPage.cpp`, beside the storage managers Safari 7's
  Privacy pane uses, and answered from the default data store. 601 only served IndexedDB through them; the
  other type bits map onto the matching website data types.

The rest of the surface was compared three ways:

- **C signatures.** The declarations of all 599 C functions in WebKit 537.78.2 (Safari 7.0.6) and 601.7.8
  differ only in the client and provider struct parameters (`WKBundlePageLoaderClient *` became
  `WKBundlePageLoaderClientBase *`, the same pointer to a versioned struct), `_WKUserScriptInjectionTime`'s
  name, `CF_RETURNS_RETAINED` / `NS_RETURNS_RETAINED` on the CF and NS bridges, the 8 additions above, and
  `WKPageCopySessionState` / `WKPageRestoreFromSessionState` taking a `WKTypeRef` for a `WKDataRef`.
  Upstream still hands back a `WKDataRef` there unless the context's low bit asks otherwise, and Safari 9
  imports the same `WKData` accessors Safari 7 reads it with.
- **Client versions.** Safari 9 registers these struct versions (read from each `Safari::WK::*Client::kit()`
  in its disassembly); every one is a version this tree defines:
  WKPageUIClient 6, WKPageLoaderClient 4, WKPagePolicyClient 1, WKPageContextMenuClient 3,
  WKPageFormClient 0, WKPageFindClient 0, WKContextClient 1, WKContextInjectedBundleClient 1,
  WKContextHistoryClient 0, WKContextDownloadClient 0, WKCookieManagerClient 0, WKIconDatabaseClient 1,
  WKGeolocationProvider 1, WKNotificationProvider 0, WKBundleClient 1, WKBundlePageLoaderClient 7,
  WKBundlePageUIClient 2, WKBundlePageFormClient 2, WKBundlePageResourceLoadClient 1,
  WKBundlePagePolicyClient 0, WKBundlePageContextMenuClient 0, WKBundlePageOverlayClient 0,
  WKBundlePageBannerClient 0, WKBundlePageDiagnosticLoggingClient 0 (a no-op here, as for Safari 7).
  WKPageUIClient 6 is the version whose alert, confirm and prompt callbacks answer through the result
  listeners above.
- **Objective-C.** Safari 9 binds the same classes as Safari 7 (`WKView`, `WKBrowsingContextController`,
  `WKWebInspectorProxyObjCAdapter` and the 15 WebKitLegacy ones). Every `WKView` and
  `WKBrowsingContextController` selector of 601's API that Safari 9's method-name table holds is
  implemented here, apart from `_rootLayer`, which Safari 9 never sends: the name belongs to properties
  of its own `GestureSnapshotSwipeView` and `UnifiedField`.

## Where the binds resolve

In 601, WebKit.framework is the WK2 framework and re-exports WebKitLegacy, so Safari 9 binds everything
"from WebKit". Here WebKit.framework is WebKitLegacy and WK2 is WebKit2.framework, which already
re-exports WebKitLegacy (`WebKitPlatformAquaWebKit.cmake`). Making WebKitLegacy re-export WebKit2 as well
would close a re-export cycle, and 10.9's dyld follows re-exports recursively with no record of where it
has been, so a lookup that misses (a weak import, a `dlsym`) would recurse until the stack runs out. It
would also load all of WK2 into every WebKitLegacy client on the system.

`safari9.sh install` therefore changes the one load command in the staged Safari.framework that names
`WebKit.framework/Versions/A/WebKit` to name `WebKit2.framework/Versions/A/WebKit2` (the header has room),
then signs the bundle ad hoc. All 627 binds then resolve through WebKit2 and, for the 24 WK1 symbols,
its re-export of WebKitLegacy. The same file is Safari's WebProcess plug-in: Safari passes
`[NSBundle bundleWithIdentifier:@"com.apple.Safari.framework"].bundlePath`, the staged path, so the
WebContent processes, which do not search the staged directory, load the edited binary too.
`check-abi-gap.sh` holds WebKit2 to that contract (`host-abi/safari9-needs-from-WebKit2.txt`).

## The inspector frontend

The port drives 10.9's classic Web Inspector frontend through the bridge in
`source/WebCore/inspector/InspectorFrontendClassicBridge.h`, which follows 10.9's frontend. The staged
WebInspectorUI is 601's and, where it is newer than 10.9's, outranks it in Safari's process, so
`safari9.sh install` moves it into the backup. The rest of the staged 601 engine stays where Apple put it:
it is unused while this port is installed, and it is what Safari 9 runs on again if the stock frameworks
are restored.

## Commands

```
sudo bash AquaWebKitSupport/safari9/safari9.sh install   # run by install.sh when Safari 9 is present
sudo bash AquaWebKitSupport/safari9/safari9.sh restore   # Safari 9 as Apple shipped it
bash AquaWebKitSupport/safari9/safari9.sh status         # which load command, which staged frameworks win
```

The originals are kept once in `stock-webkit-backup/safari9` beside the checkout. Safari 9 installed
after the port needs `safari9.sh install` run once by hand.

## Recapturing the contract

From the staged Safari.framework on a 10.9 machine with Safari 9 installed (before `safari9.sh install`):

```
F=/System/Library/StagedFrameworks/Safari/Safari.framework/Versions/A/Safari
nm -gu "$F" | awk '{print $NF}' | sort -u > safari9-imports.txt
nm -m -u "$F" | awk '/\(from WebKit\)$/ {print $(NF-2)}' | sort -u > safari9-needs-from-WebKit2.txt
```

The checked-in lists were taken from the payload of Apple's `Safari9.1.3Mavericks.pkg` with
`llvm-objdump --macho --bind --lazy-bind`, which gives the same 627.

## Still to verify on 10.9

The comparisons above are static. On a 10.9.5 machine with Safari 9.1.3 and this port installed:
launch and browsing in several tabs; back/forward and session restore after relaunch; downloads, and
resuming a stopped one; JavaScript alert, confirm and prompt; History, Top Sites and the tab view;
Preferences ▸ Privacy ▸ Details (the origin-data manager) and Remove All Website Data; Reader;
Develop ▸ Show Web Inspector; Safari extensions.
