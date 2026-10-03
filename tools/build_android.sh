#!/usr/bin/env bash
# Local Android export helper.
#   tools/build_android.sh debug     -> build/android/InfiniteLoopAscension-debug.apk
#   tools/build_android.sh release   -> signed release APK (needs keystore env vars)
#   tools/build_android.sh aab       -> signed release AAB (gradle build template)
#
# Requirements: Godot 4.7.x with Android export templates installed, Android
# SDK path + Java configured in Godot's editor settings (see
# docs/BUILD_ANDROID.md). Release builds read:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
set -euo pipefail
GODOT="${GODOT:-godot}"
MODE="${1:-debug}"
cd "$(dirname "$0")/.."
mkdir -p build/android
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
case "$MODE" in
  debug)
    "$GODOT" --headless --path . --export-debug "Android" build/android/InfiniteLoopAscension-debug.apk ;;
  release)
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?set the release keystore env vars}"
    "$GODOT" --headless --path . --export-release "Android" build/android/InfiniteLoopAscension-release.apk ;;
  aab)
    : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?set the release keystore env vars}"
    "$GODOT" --headless --path . --install-android-build-template --export-release "Android AAB" build/android/InfiniteLoopAscension-release.aab ;;
  *)
    echo "usage: $0 [debug|release|aab]" >&2; exit 2 ;;
esac
ls -la build/android
