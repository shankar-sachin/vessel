#!/usr/bin/env bash
# Every package's tests, then iPhone, iPad and Apple Watch builds, failing on
# any compiler warning. This is what makes "zero warnings" checked rather than
# remembered.
#
#   scripts/test-all.sh            packages + builds
#   scripts/test-all.sh --ui       also the XCUITest suite on iPhone (10–20 min)
#   scripts/test-all.sh --release  also a Release archive, as App Store Connect receives it

source "$(dirname "$0")/lib.sh"

RUN_UI=0; RUN_RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --ui) RUN_UI=1 ;;
    --release) RUN_RELEASE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

LOGS="$ROOT/build/logs"; mkdir -p "$LOGS"

for pkg in "${PACKAGES[@]}"; do
  step "swift test — $pkg"
  swift test --package-path "Packages/$pkg" 2>&1 | tee "$LOGS/test-$pkg.log" | grep -E '✔|✘|passed|failed|error:' | tail -5
  # tee hides swift test's exit status from pipefail's view of the grep; check it.
  [[ "${PIPESTATUS[0]}" -eq 0 ]] || { tail -40 "$LOGS/test-$pkg.log" >&2; false; }
done

step "Generating the Xcode project"
xcodegen generate --quiet

build() {  # build <label> <destination> [extra xcodebuild args…]
  local label="$1" dest="$2"; shift 2
  step "$label build"
  local log="$LOGS/build-${label// /-}.log"
  if ! xcodebuild -project Vessel.xcodeproj -scheme "${SCHEME:-Vessel}" -configuration Debug \
       -destination "$dest" "$@" build >"$log" 2>&1; then
    grep -E 'error:' "$log" | sort -u >&2 || tail -40 "$log" >&2
    return 1
  fi
  assert_no_warnings "$log"
  ok "$label: built, zero warnings"
}

build "iPhone" "id=$(device_id "$IPHONE_NAME")"
build "iPad" "id=$(device_id "$IPAD_NAME")"
SCHEME=VesselWatch build "Watch" "id=$(device_id "$WATCH_NAME")"

if (( RUN_RELEASE )); then
  step "Release archive"
  log="$LOGS/archive.log"
  rm -rf build/Vessel.xcarchive
  xcodebuild -project Vessel.xcodeproj -scheme Vessel -configuration Release \
    -destination 'generic/platform=iOS' -archivePath build/Vessel.xcarchive \
    archive CODE_SIGNING_ALLOWED=NO >"$log" 2>&1 || { tail -40 "$log" >&2; false; }
  assert_no_warnings "$log"
  app=build/Vessel.xcarchive/Products/Applications/Vessel.app
  for f in "$app/PrivacyInfo.xcprivacy" "$app"/Watch/*.app/PrivacyInfo.xcprivacy; do
    [[ -f "$f" ]] || { echo "missing privacy manifest: $f" >&2; false; }
  done
  ok "Release archive: zero warnings, privacy manifests present"
fi

if (( RUN_UI )); then
  step "UI tests on $IPHONE_NAME"
  rm -rf build/ui.xcresult
  xcodebuild -project Vessel.xcodeproj -scheme Vessel \
    -destination "id=$(device_id "$IPHONE_NAME")" \
    -resultBundlePath build/ui.xcresult test >"$LOGS/ui.log" 2>&1 \
    || { grep -E "error:|failed" "$LOGS/ui.log" | tail -30 >&2; false; }
  ok "UI suite passed"
fi

printf "\n\033[1;32mAll checks passed.\033[0m\n"
