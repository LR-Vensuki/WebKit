AquaWebKit for OS X 10.9 Mavericks — preview

Known issue in this update: one long-running HLS session caused WebContent to
crash with an invalid memory free in GStreamer. Short playback, quality changes
and ten seek/close cycles passed afterward, but the cause is not fixed.
This is an experimental build. See VALIDATION.txt for the tested scope.

Modern WebKit as the system WebKit of OS X 10.9, for Safari 7 and for Safari 9.1.3.
Installing it affects almost every app that shows web content, so keep a Time Machine backup.

Install
  1. Double-click "Install AquaWebKit.command" and enter your administrator password in Terminal.
  2. Restart the Mac.
  The frameworks it replaces are copied to the AquaWebKit-backup folder in your home folder.
  With Safari 9.1.3 installed, it also points Safari 9 at the new frameworks; installing
  Safari 9 later needs the installer run once more.

Undo
  1. Double-click "Restore Stock WebKit.command".
  2. Restart the Mac.

The disk image was built from the safari9 branch of the AquaWebKit backport
(github.com/LR-Vensuki/WebKit), based on github.com/Wowfunhappy/WebKit.
See BUILD-INFO.txt for the exact revision.
