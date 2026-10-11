# QuickTime handoff rig

Generate the media with the vendored GStreamer runtime:

```sh
AquaWebKitSupport/toolchain/build/python3/bin/python3 AquaWebKitSupport/tests/legacy-extensions/generate-quicktime-media.py
AquaWebKitSupport/toolchain/build/python3/bin/python3 AquaWebKitSupport/tests/legacy-extensions/server.py
```

Load `AquaWebKitSupport/extensions/SendToQuickTime.safariextension` in Safari 7's Extension Builder. Open `http://127.0.0.1:8843/quicktime.html` and select a fixture. The toolbar's QuickTime button and the video's context menu exercise the engine API. The generated files stay under the ignored `build/quicktime-media/` directory. Its HTTP endpoint supports HEAD and single byte ranges.

For MP4 and native HLS, check that QuickTime opens the URL, the browser video pauses, and closing the tab leaves QuickTime playing. Check that ordinary page JavaScript reports `typeof aqua === "undefined"`.

For MSE, use the H.264/AAC, VP9/Opus, and VP8/Vorbis fixtures. The latter two distinguish container-compatible pass-through from transcoding. QuickTime 10.3 playback checks apply to H.264/AAC. Inspect VP9/Opus TS output with the vendored GStreamer decoder; decoder support in the installed QuickTime version does not choose the restream codec.

Check seeking to the middle and near the end, pausing for at least a minute, closing the Safari tab during playback, and closing the movie while leaving QuickTime running. Compare crash reports before and after testing.
