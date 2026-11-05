# kdeclip

Phone → PC clipboard for KDE Connect, on Android, where it normally doesn't work.

## The problem

You copy something on your phone. Nothing appears on your PC. Copy on the PC and it lands on the phone just fine.

That's not KDE Connect being broken. Since Android 10 the system refuses clipboard reads to any app that isn't in the foreground, isn't the keyboard, and isn't a system service. KDE Connect sits in the background, so its read comes back empty and it has nothing to send. You can see the refusal in logcat:

```
E ClipboardService: Denying clipboard access to org.kde.kdeconnect_tp, application is not in focus nor is it a system service for user 0
```

No setting in KDE Connect changes that. It happens inside the phone's own clipboard service, before the app's code even runs.

## What this does

It hooks one function inside system_server — `ClipboardService#clipboardAccessAllowed`, the one that produces that log line — and answers "yes" when the caller is KDE Connect. Everyone else still gets the normal answer.

KDE Connect carries on doing all the syncing itself. This module doesn't read your clipboard, doesn't keep a copy of it, and doesn't send anything anywhere. It only removes a "no" that shouldn't apply to an app you trust.

## What you need first

Read this before downloading, because without the first two items the module does nothing:

- **Root**, via KernelSU or Magisk.
- **An Xposed framework**: Vector (what this was built and tested against) or a recent LSPosed. Root alone isn't enough — the framework is what allows a module to run inside system_server, where the clipboard service lives.
- KDE Connect installed and paired on both the phone and the PC, with the clipboard plugin enabled on both sides.
- Android 10 or newer. Tested on a Galaxy S26 Ultra running Android 16 / One UI 9.

If you're not rooted, this is the wrong tool and it will simply do nothing.

## Install

1. Download `kdeclip-v1.3.0.apk` from Releases, or `adb install kdeclip-v1.3.0.apk`.
2. Open Vector → Modules → **KDE Clipboard Access** → switch it on. There's no scope to select; the module already declares `system` in its own metadata.
3. Reboot. Modules that run inside system_server only load at boot.
4. Copy something on the phone, paste on the PC.

## Did it work

```
adb logcat -s kdeclip
```

On boot you should see `hooked clipboardAccessAllowed/7`. Every time you copy, `allowing org.kde.kdeconnect_tp via clipboardAccessAllowed`.

## Things worth knowing

- Only `org.kde.kdeconnect_tp` is whitelisted. Every other app is untouched.
- The `Denying clipboard access ...` line can still show up in logcat right before the override. That's the framework logging its own decision before the module replaces it.
- **Vector says "no APK attached"?** The APK went in as an incremental install, which leaves no readable file behind. Reinstall with `adb install --no-incremental`.
- **Samsung phones** freeze background apps aggressively. If sync stops after a while, whitelist KDE Connect:
  `adb shell cmd deviceidle whitelist +org.kde.kdeconnect_tp`
- **To remove it:** switch the module off in Vector, reboot, uninstall the app. Nothing is left behind.

## Build

```
bash build.sh
```

Needs a JDK 17+ (`JAVA_HOME`), the Android SDK with build-tools installed (`ANDROID_HOME`), curl and python3. The Xposed API is pulled from Maven Central on the first run and cached in `libs/`. Signing uses `keys/kdeclip.keystore`, generated on the first build — keep it, updates have to be signed with the same key.

Layout:

```
module/                  the APK itself
  AndroidManifest.xml
  src/                   Module.java - the whole module
  META-INF/xposed/       module.prop, java_init.list, scope.list (system)
  assets/xposed_init
build.sh
```

## License

MIT. See LICENSE.
