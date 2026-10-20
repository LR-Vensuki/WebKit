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
then takes the binary's code signature off: the edit voids Apple's, and the kernel kills a process that
maps a page whose signature no longer matches, while 10.9 loads unsigned frameworks. (An ad-hoc signature
would need codesign, which only runs an Apple-signed `codesign_allocate`, so not on a Mac without the
Command Line Tools.) All 627 binds then resolve through WebKit2 and, for the 24 WK1 symbols,
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

## Tested on 10.9

In a 10.9.5 virtual machine with Safari 9.1.3 and this port installed, on a Penryn CPU model with and
without RDTSCP and SSE4.2 (no AVX either way):

- Sites, with no WebContent crash: YouTube (MSE video plays), GitHub, Wikipedia, Google, Yandex, VK,
  Twitch (WebAssembly), Figma, Discord, Spotify, Netflix, Telegram Web, X, Apple, Apple Maps and the
  WebGL Aquarium (WebGL), OpenStreetMap, Stack Overflow, Amazon, CNN, BBC, The New York Times,
  Speedtest, Speedometer 3.1.
- Safari: Reader, Develop ▸ Show Web Inspector, Preferences ▸ Privacy ▸ Details (the origin-data
  manager lists sites and removes one), downloads, Private Browsing (a separate data store).
- Not yet tested: back/forward and session restore after relaunch, resuming a stopped download,
  JavaScript alert/confirm/prompt, History, Top Sites and the tab view, Safari extensions.

Three crashes on Macs without AVX or RDTSCP (Core 2, Nehalem, Westmere, all of which run 10.9) came up
here and are fixed on this branch; none is specific to Safari 9:

- JavaScriptCore assumed AVX on Darwin and emitted VEX encodings from the JIT; it now asks the kernel
  (`hw.optional.avx1_0`).
- The JIT probe trampoline saved the vector registers with `vmovaps`, which killed WebAssembly workers;
  Darwin now builds the SSE/AVX pair upstream builds elsewhere and picks one by AVX support.
- abseil's benchmark timer ran `rdtscp` in a static initializer of libwebrtc, so every WebKit client
  died at launch on Core 2; it now runs on first use, which WebKit never makes.


## Upstream update validation (2026-10-15–16)

Merge `9528be21a75` includes the upstream changes through `0c316cbbdfa0` and GStreamer 1.28.7.
`f18c996e4ee` removes a legacy HLS plug-in left in the dependency install prefix by an earlier
build; that obsolete plug-in imports symbols the new runtime no longer exports. The resumed
build completed, the absent-reference audit passed for all 250 staged binaries and their slices,
and the Safari ABI audit found zero missing symbols (138 JavaScriptCore, 307 WebKit and 690 WebKit2).

The updated frameworks were installed in the 10.9.5 VM with Safari 9.1.3 on a Penryn CPU model
without AVX. The following checks passed:

- YouTube's Big Buck Bunny video played at 854×480; its playback time advanced from 41.70 to
  54.98 seconds across the measurement interval, with no media error.
- Twitch's public homepage, GitHub's WebKit repository, Wikipedia's Safari article, Figma's public
  homepage, Telegram's QR login page and Google search loaded. No new crash reports or crash
  events appeared during these page checks. This does not establish compatibility with signed-in
  apps, Figma's editor, Twitch live playback or DRM services.
- A WebAssembly add function returned 42 after 50,000 calls. WebGL Aquarium rendered fish with
  a valid WebGL context, at about 7 fps in this VM; that is not a hardware performance benchmark.
- The Mux Big Buck Bunny HLS sample played directly at 320×184 and 1280×720 for approximately
  50 seconds each. The adaptive master switched from 720p through 480p to 1080p while playback
  continued. Ten subsequent create/play/seek/close cycles and a seek to the final seconds followed
  by end-of-stream and teardown produced no new crash reports.

The first adaptive-stream run stalled, and a later operation in that WebContent process aborted
with an invalid free in `_gst_event_free`, reached from `gst_audio_decoder_finish_frame_or_subframe`
on a `multiqueue` audio thread. The cause is in GStreamer itself (also unchanged on its main
branch): `gst_audio_decoder_handle_gap()` queues a GAP that arrives while fdkaacdec has pushed only
part of a frame as subframes, and then also unrefs it, so the queue later pushes a freed event.
`deps/patches/gst-plugins-base-audiodecoder-queued-gap-ownership.patch` drops the extra unref.

With that patch built in (2026-10-19), on the same VM and CPU model:

- Ten create/play/seek/close cycles on the Mux HLS master, and its 10.5-minute film played from the
  start through end-of-stream, with no crash.
- Apple's bipbop advanced fMP4 HLS master played for 10 minutes (489 s of media at up to 1080p),
  with no crash.

The origin-data manager also names cookies by host now, as `WebsiteDataStore` keeps them, so a
per-site removal of the cookie type reaches them; this was fixed from review, not exercised in Safari.
