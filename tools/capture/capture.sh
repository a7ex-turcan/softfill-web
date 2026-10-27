#!/bin/zsh
# Captures the real app for Home: the hero's screen recording on iPad and the Devices section's stills on iPad and
# iPhone, in en, de, ro and ru. Recipe and reasons: CLAUDE.md, Assets, Screenshots.
#
#   tools/capture/capture.sh <work-dir> [step ...]      steps, in order: sims build seed record export encode clean
#                                                       (no step: every step but clean)
#
# <work-dir> holds everything the run makes (DerivedData, result bundles, recordings, captures); keep it outside the
# repo. Needs ../softfill checked out next to this repo, Xcode 27 with the iOS 27.0 simulator runtime.
set -e
setopt null_glob
WORK="${1:?usage: tools/capture/capture.sh <work-dir> [step ...]}"; shift
if [ $# -eq 0 ]; then STEPS=(sims build seed record export encode); else STEPS=("$@"); fi
WEB="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$(cd "$WEB/../softfill" && pwd)"
SCRATCH="$APP/SoftfillUITests/HeroCaptureScratchTests.swift"
LANGS=(${=CAPTURE_LANGS:-en de ro ru})   # CAPTURE_LANGS="de" redoes one language
typeset -A TESTS=(en test2CaptureEnglish de test3CaptureGerman ro test4CaptureRomanian ru test5CaptureRussian)
IPAD_NAME="Softfill Web iPad Pro 13"
PHONE_NAME="Softfill Web iPhone 17"
RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-27-0
mkdir -p "$WORK/sig" "$WORK/raw" "$WORK/rec"
# The scratch test is never left in the app repo, whatever happens.
trap 'rm -f "$SCRATCH"' EXIT INT TERM

udid() { xcrun simctl list devices -j | python3 -I -c 'import json,sys
n=sys.argv[1]
for rt, ds in json.load(sys.stdin)["devices"].items():
    for d in ds:
        if d["name"] == n and d["isAvailable"]: print(d["udid"]); sys.exit()' "$1"; }

prepare_sim() { # name devicetype
  local u; u=$(udid "$1")
  [ -n "$u" ] || u=$(xcrun simctl create "$1" "$2" "$RUNTIME")
  xcrun simctl boot "$u" 2>/dev/null || true
  xcrun simctl bootstatus "$u" -b >/dev/null
  # English (US) region and a 12-hour clock, so the status bar reads 9:41; then a reboot to apply them.
  xcrun simctl spawn "$u" defaults write -g AppleLocale en_US
  xcrun simctl spawn "$u" defaults write -g AppleLanguages -array en
  xcrun simctl spawn "$u" defaults write -g AppleICUForce24HourTime -bool false
  xcrun simctl shutdown "$u"; xcrun simctl boot "$u"; xcrun simctl bootstatus "$u" -b >/dev/null
  xcrun simctl ui "$u" appearance light
  xcrun simctl status_bar "$u" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" --batteryState discharging --batteryLevel 100
  echo "$1: $u"
}

run_test() { # udid test bundle-name
  rm -rf "$WORK/$3.xcresult"
  ( cd "$APP" && TEST_RUNNER_CAPTURE_DIR="$WORK/sig" xcodebuild test-without-building -scheme Softfill \
      -destination "platform=iOS Simulator,id=$1" -derivedDataPath "$WORK/dd" \
      -only-testing:"SoftfillUITests/HeroCaptureScratchTests/$2" -resultBundlePath "$WORK/$3.xcresult" \
      > "$WORK/$3.log" 2>&1 ) || { echo "$2 failed on $1: see $WORK/$3.log"; return 1; }
  echo "$2 passed ($3)"
}

wait_file() { local n=0; while [ ! -f "$1" ]; do sleep 0.1; n=$((n + 1)); [ $n -lt 1800 ] || return 1; done; }

record_lang() { # lang: runs the capture on iPad while the host records the screen
  local lang=$1 test=$2 mov="$WORK/rec/ipad-$1.mp4"
  rm -f "$WORK/sig/"*"-$lang"
  run_test "$IPAD" "$test" "ipad-$lang" &
  local runner=$!
  wait_file "$WORK/sig/ready-$lang" || { echo "the canvas never opened ($lang)"; return 1; }
  xcrun simctl io "$IPAD" recordVideo --codec=h264 --force "$mov" 2> "$WORK/rec/ipad-$lang.log" &
  local recorder=$!
  local n=0
  until grep -q "Recording started" "$WORK/rec/ipad-$lang.log"; do
    sleep 0.05; n=$((n + 1)); [ $n -lt 400 ] || { echo "the recording never started ($lang)"; return 1; }
  done
  python3 -I -c 'import time; print(time.time())' > "$WORK/sig/started-$lang"
  touch "$WORK/sig/recording-$lang"
  wait_file "$WORK/sig/done-$lang" || { echo "the taps never finished ($lang)"; kill -INT $recorder; return 1; }
  kill -INT $recorder; wait $recorder || true
  touch "$WORK/sig/stopped-$lang"
  wait $runner
}

for step in $STEPS; do
  IPAD=$(udid "$IPAD_NAME"); PHONE=$(udid "$PHONE_NAME")
  case $step in
    sims)
      prepare_sim "$IPAD_NAME" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB
      prepare_sim "$PHONE_NAME" com.apple.CoreSimulator.SimDeviceType.iPhone-17 ;;
    build)
      cp "$WEB/tools/capture/HeroCaptureScratchTests.swift" "$SCRATCH"
      ( cd "$APP" && xcodebuild build-for-testing -scheme Softfill -destination 'generic/platform=iOS Simulator' \
          -derivedDataPath "$WORK/dd" > "$WORK/build.log" 2>&1 ) || { echo "build failed: $WORK/build.log"; exit 1; }
      rm -f "$SCRATCH"
      echo "built" ;;
    seed)
      for u in $IPAD $PHONE; do xcrun simctl uninstall "$u" nutrx-labs.softfill || true; done
      run_test "$IPAD" test1Seed seed-ipad
      run_test "$PHONE" test1Seed seed-iphone ;;
    record)
      for lang in $LANGS; do
        record_lang $lang ${TESTS[$lang]}
        run_test "$PHONE" ${TESTS[$lang]} "iphone-$lang"
      done ;;
    export)
      for bundle in "$WORK"/{ipad,iphone}-${^LANGS}.xcresult; do
        name=$(basename "$bundle" .xcresult)
        rm -rf "$WORK/att-$name"
        xcrun xcresulttool export attachments --path "$bundle" --output-path "$WORK/att-$name" >/dev/null
        python3 -I - "$WORK/att-$name" "$WORK/raw" <<'PY'
import json, pathlib, re, shutil, sys
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
for test in json.load(open(src / "manifest.json")):
    for a in test.get("attachments", []):
        m = re.match(r"((?:ipad|iphone)-[a-z]{2}-[a-z-]+?)_\d+_", a.get("suggestedHumanReadableName", ""))
        if m:
            shutil.copy(src / a["exportedFileName"], dst / (m.group(1) + ".png"))
PY
      done
      ls "$WORK/raw" ;;
    encode)
      swiftc -O "$WEB/tools/capture/encode.swift" -o "$WORK/encode"
      "$WORK/encode" "$WORK" "$WEB/src/assets" $LANGS ;;
    clean)
      for u in $IPAD $PHONE; do
        xcrun simctl status_bar "$u" clear || true
        xcrun simctl shutdown "$u" 2>/dev/null || true
        xcrun simctl delete "$u"
      done
      echo "deleted the capture simulators" ;;
    *) echo "unknown step $step"; exit 1 ;;
  esac
done
