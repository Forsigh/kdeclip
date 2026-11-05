# kdeclip

Copy on your phone, paste on your PC. KDE Connect already handles the easy direction; this fixes the one it can't.

Android won't let a background app read the clipboard. KDE Connect isn't on screen, isn't your keyboard and isn't a system service, so it gets refused and has nothing to send, and nothing inside KDE Connect changes that. This module hooks the check in the phone's system process and answers yes when the caller is KDE Connect. Every other app still gets the ordinary answer, KDE Connect still does all the syncing, and the module never reads or sends anything by itself.

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
