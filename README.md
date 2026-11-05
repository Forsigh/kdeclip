# kdeclip

KDE Connect's copy from phone to PC has been broken since Android 10, and it isn't KDE Connect's fault. Android stopped letting background apps read the clipboard, which is the one thing KDE Connect needs to do to send it. This module lifts that restriction for KDE Connect alone, so copied text starts arriving on the PC again.

The restriction is a check inside the phone's system process. When it sees KDE Connect asking, this module answers yes instead of no. Every other app still gets the ordinary answer, KDE Connect still does all the syncing, and the module never reads or sends anything by itself.

None of this is new or unusual to your phone. People have been reporting it to KDE since Android 10 shipped, and the current report, [bug 525992](https://bugs.kde.org/show_bug.cgi?id=525992), is still open. The app can't fix it from the inside, which is why the fix has to live in the system process.

> You need root, through KernelSU or Magisk, plus Vector (what this was tested on) or a recent LSPosed. Without those it does nothing, so there's no point installing it.

## Install

1. Install the APK from Releases, or `adb install --no-incremental kdeclip-v1.3.0.apk`
2. Open Vector, go to Modules, switch on KDE Clipboard Access. Nothing to configure.
3. Reboot, since the module starts with the system process.
4. Copy on the phone, paste on the PC.

## If it doesn't work

`adb logcat -s kdeclip` shows whether the hook loaded. A `Denying clipboard access` line is normal: Android logs its own decision, then the module replaces it. But if Vector says the module has no APK attached, the install was incremental and left no readable file, so reinstall with `adb install --no-incremental`.

## Build

Run `bash build.sh` with a JDK 17 or newer, the Android SDK, curl and python. The whole module is `module/src/com/forsigh/kdeclip/Module.java`.

MIT.
