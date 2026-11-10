#!/usr/bin/env bash
# Build the one-shot app without Gradle: aapt2 + javac + d8 + apksigner.
# Needs: Android SDK (build-tools 35, platform 35) and a JDK 17+ (a JRE with the jdk.compiler module works).
# Signing: KEYSTORE / KS_PASS / KS_ALIAS env vars, defaulting to the Android debug keystore.
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
BT=$SDK/build-tools/${BUILD_TOOLS:-35.0.0}
JAR=$SDK/platforms/android-35/android.jar
KEYSTORE=${KEYSTORE:-$HOME/.android/debug.keystore}
KS_PASS=${KS_PASS:-android}
KS_ALIAS=${KS_ALIAS:-androiddebugkey}
VER=$(sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' AndroidManifest.xml)
B=build
rm -rf $B && mkdir -p $B/assets/webroot $B/assets/scripts $B/classes $B/gen ../dist

# shared backend + UI from the module
cp ../module/webroot/index.html $B/assets/webroot/
cp ../module/lib.sh ../module/ctl.sh $B/assets/scripts/

"$BT/aapt2" compile --dir res -o $B/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -A $B/assets \
  --java $B/gen -o $B/app.unaligned.apk $B/res.zip

if command -v javac >/dev/null 2>&1; then JAVAC=(javac); else JAVAC=(java -m jdk.compiler/com.sun.tools.javac.Main); fi
"${JAVAC[@]}" -source 8 -target 8 -Xlint:-options -nowarn -encoding UTF-8 -bootclasspath "$JAR:$BT/core-lambda-stubs.jar" -cp "$JAR" -d $B/classes \
  $(find src $B/gen -name '*.java')

"$BT/d8" --release --min-api 29 --lib "$JAR" --output $B $(find $B/classes -name '*.class')
(cd $B && zip -q app.unaligned.apk classes.dex)

"$BT/zipalign" -p -f 4 $B/app.unaligned.apk $B/app.aligned.apk
OUT=../dist/gwallet-cardart-app-v$VER.apk
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" --ks-key-alias "$KS_ALIAS" --v4-signing-enabled false \
  --out "$OUT" $B/app.aligned.apk
"$BT/apksigner" verify "$OUT"
echo "$OUT"
