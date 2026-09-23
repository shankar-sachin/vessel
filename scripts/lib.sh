# Shared helpers for Vessel's scripts. Source it; don't run it.
#
#   step "Building the app"      prints a header and records the current step
#   device_id "iPhone 17 Pro"    the UDID of an available simulator by name
#
# On any failure the ERR trap names the step that was running, so a CI log
# says "FAILED during: iPad build" rather than just a non-zero exit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CURRENT_STEP="setup"
trap 'printf "\n\033[1;31m✗ FAILED during: %s\033[0m\n" "$CURRENT_STEP" >&2' ERR

step() {
  CURRENT_STEP="$1"
  printf "\n\033[1;34m▸ %s\033[0m\n" "$1"
}

ok() { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }

# Simulator ids differ per machine, so look devices up by name. Newest runtime
# wins when a name exists on several.
device_id() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True):
            found.append((runtime, d["udid"]))
if not found:
    sys.exit("no available simulator named " + repr(name))
print(sorted(found)[-1][1])
' "$1"
}

IPHONE_NAME="${VESSEL_IPHONE:-iPhone 17 Pro}"
IPAD_NAME="${VESSEL_IPAD:-iPad Pro 13-inch (M5)}"
WATCH_NAME="${VESSEL_WATCH:-Apple Watch Series 11 (46mm)}"

PACKAGES=(VesselCore VesselDesign VesselActivities VesselNutrition VesselIntelligence VesselVision VesselInsights VesselIntents)

# Xcode's App Intents metadata step prints this for every target without
# intents. It has no switch and is not a code warning.
KNOWN_NOTICE='Metadata extraction skipped'

# Fails if a build log holds any warning other than the known notice.
assert_no_warnings() {
  local log="$1" found
  found="$(grep -E '(^|: )warning: ' "$log" | grep -v "$KNOWN_NOTICE" | sort -u || true)"
  if [[ -n "$found" ]]; then
    echo "$found" >&2
    echo "Build produced warnings (log: $log)" >&2
    return 1
  fi
}
