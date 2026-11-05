#!/usr/bin/env bash
# Builds the kdeclip APK without Gradle: javac -> d8 -> aapt2 -> zip -> zipalign -> apksigner.
#
# Needs: a JDK 17+ (JAVA_HOME), the Android SDK with build-tools 33+ and one platform
# (ANDROID_HOME), curl and python3. The Xposed API jar is fetched from Maven Central once
# and cached in libs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODULE="$ROOT/module"
OUT="$ROOT/build"
KEYS="$ROOT/keys"
LIBS="$ROOT/libs"
LIBXPOSED="102.0.0"
KS="$KEYS/kdeclip.keystore"
KSPASS="kdeclip"

native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) CPSEP=";" ;;
  *)                    CPSEP=":" ;;
esac
pick() { # tolerate .exe / .bat on Windows
  for candidate in "$1" "$1.exe" "$1.bat"; do
    if [ -x "$candidate" ] || [ -f "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  done
  printf '%s\n' "$1"
}

# --- tools ----------------------------------------------------------------
if [ -n "${JAVA_HOME:-}" ] && { [ -x "$JAVA_HOME/bin/javac" ] || [ -f "$JAVA_HOME/bin/javac.exe" ]; }; then
  JBIN="$JAVA_HOME/bin"
elif command -v javac >/dev/null 2>&1; then
  JBIN="$(dirname "$(command -v javac)")"
else
  echo "No JDK found. Set JAVA_HOME to a JDK 17 or newer." >&2
  exit 1
fi
JAVAC="$(pick "$JBIN/javac")"
JAR="$(pick "$JBIN/jar")"
KEYTOOL="$(pick "$JBIN/keytool")"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  echo "No Android SDK found. Set ANDROID_HOME to your SDK directory." >&2
  exit 1
fi
BT="$(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V | tail -1 || true)"
AJAR="$(ls -d "$SDK"/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1 || true)"
if [ -z "$BT" ] || [ -z "$AJAR" ]; then
  echo "The SDK at $SDK has no build-tools or no platform installed." >&2
  exit 1
fi
D8="$(pick "$BT/d8")"
AAPT2="$(pick "$BT/aapt2")"
ZIPALIGN="$(pick "$BT/zipalign")"
APKSIGNER="$(pick "$BT/apksigner")"

if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi

# --- Xposed API -----------------------------------------------------------
mkdir -p "$LIBS"
if [ ! -f "$LIBS/libxposed-api.jar" ]; then
  echo "== fetching libxposed api $LIBXPOSED"
  mkdir -p "$OUT"
  curl -fsSL -o "$(native_path "$OUT/api.aar")" \
    "https://repo1.maven.org/maven2/io/github/libxposed/api/${LIBXPOSED}/api-${LIBXPOSED}.aar"
  "$PY" - "$OUT/api.aar" "$LIBS/libxposed-api.jar" <<'PY'
import sys, zipfile

src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as aar:
    open(dst, "wb").write(aar.read("classes.jar"))
PY
  rm -f "$OUT/api.aar"
fi

# --- build ----------------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT/classes" "$OUT/dex" "$KEYS"

echo "== 1/7 javac"
: > "$OUT/sources.txt"
while IFS= read -r f; do native_path "$f" >> "$OUT/sources.txt"; done < <(find "$MODULE/src" -name '*.java')
CP="$(native_path "$AJAR")${CPSEP}$(native_path "$LIBS/libxposed-api.jar")"
"$JAVAC" -source 8 -target 8 -nowarn -cp "$CP" -d "$(native_path "$OUT/classes")" \
  "@$(native_path "$OUT/sources.txt")" > "$OUT/javac.log" 2>&1 \
  || { cat "$OUT/javac.log"; echo "javac failed" >&2; exit 1; }
echo "   classes: $(find "$OUT/classes" -name '*.class' | wc -l | tr -d ' ')"

echo "== 2/7 jar"
"$JAR" --create --file "$(native_path "$OUT/classes.jar")" -C "$(native_path "$OUT/classes")" .

echo "== 3/7 d8"
"$D8" --lib "$(native_path "$AJAR")" --min-api 33 --output "$(native_path "$OUT/dex")" \
  "$(native_path "$OUT/classes.jar")" >/dev/null
test -f "$OUT/dex/classes.dex" || { echo "d8 produced no dex" >&2; exit 1; }

echo "== 4/7 aapt2 compile"
"$AAPT2" compile --dir "$(native_path "$MODULE/res")" -o "$(native_path "$OUT/res.zip")" >/dev/null

echo "== 5/7 aapt2 link"
"$AAPT2" link -o "$(native_path "$OUT/base.apk")" -I "$(native_path "$AJAR")" \
  --manifest "$(native_path "$MODULE/AndroidManifest.xml")" \
  -A "$(native_path "$MODULE/assets")" "$(native_path "$OUT/res.zip")" >/dev/null

echo "== 6/7 add dex + xposed metadata"
"$PY" - "$(native_path "$OUT/base.apk")" "$(native_path "$OUT/dex/classes.dex")" "$(native_path "$MODULE")" <<'PY'
import os, shutil, sys, zipfile

apk, dex, module = sys.argv[1], sys.argv[2], sys.argv[3]
tmp = apk + ".tmp"
with zipfile.ZipFile(apk) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
    for item in zin.infolist():
        zout.writestr(item, zin.read(item.filename))
    zout.write(dex, "classes.dex")
    for rel in ("META-INF/xposed/module.prop", "META-INF/xposed/java_init.list", "META-INF/xposed/scope.list"):
        zout.write(os.path.join(module, rel), rel)
shutil.move(tmp, apk)
print("   entries:", len(zipfile.ZipFile(apk).namelist()))
PY

echo "== 7/7 zipalign + sign"
"$ZIPALIGN" -f 4 "$(native_path "$OUT/base.apk")" "$(native_path "$OUT/aligned.apk")"
if [ ! -f "$KS" ]; then
  "$KEYTOOL" -genkeypair -v -keystore "$(native_path "$KS")" -storepass "$KSPASS" -keypass "$KSPASS" \
    -alias kdeclip -keyalg RSA -keysize 2048 -validity 9125 \
    -dname "CN=kdeclip, O=kdeclip, C=PL" >/dev/null 2>&1
  echo "   keystore created in keys/ - keep it, updates must be signed with the same key"
fi
VERSION="$(grep -o 'versionName="[^"]*"' "$MODULE/AndroidManifest.xml" | head -1 | cut -d'"' -f2)"
APKOUT="$ROOT/kdeclip-v${VERSION}.apk"
"$APKSIGNER" sign --ks "$(native_path "$KS")" --ks-pass "pass:$KSPASS" --key-pass "pass:$KSPASS" \
  --out "$(native_path "$APKOUT")" "$(native_path "$OUT/aligned.apk")"
echo "== done: $APKOUT"
