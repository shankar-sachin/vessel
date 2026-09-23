#!/usr/bin/env bash
# Builds Vessel and installs it on your iPhone, signed with your own Apple ID.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/shankar-sachin/vessel/main/scripts/install.sh)"
#
# or, from a clone:  scripts/install.sh
#
# Needs a Mac with Xcode 26+, signed in to your Apple ID (Xcode → Settings →
# Accounts; a free Apple ID works), and your iPhone plugged in and unlocked
# with Developer Mode on. The watch app comes along with the phone app.
#
# Environment:
#   VESSEL_DIR            where to clone (default ~/vessel)
#   VESSEL_BUNDLE_PREFIX  bundle id prefix (default derived from your team)
#   VESSEL_DEVICE         a device name or id, if more than one is connected

set -euo pipefail

CURRENT_STEP="setup"
trap 'printf "\n\033[1;31m✗ Stopped during: %s\033[0m\n" "$CURRENT_STEP" >&2' ERR
step() { CURRENT_STEP="$1"; printf "\n\033[1;34m▸ %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
die()  { printf "\n\033[1;31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

REPO_URL="https://github.com/shankar-sachin/vessel.git"

# ---------------------------------------------------------------- tools
step "Checking your Mac"
[[ "$(uname)" == "Darwin" ]] || die "Vessel builds on macOS only."
command -v xcodebuild >/dev/null || die "Xcode isn't installed. Get it free from the Mac App Store, open it once, then run this again."
XCODE_MAJOR="$(xcodebuild -version | awk '/^Xcode/ { split($2, v, "."); print v[1] }')"
(( XCODE_MAJOR >= 26 )) || die "Vessel needs Xcode 26 or later; this Mac has $(xcodebuild -version | head -1)."
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || die "Homebrew is needed to install XcodeGen. Install it from https://brew.sh and run this again."
  echo "Installing XcodeGen…"
  brew install xcodegen
fi
ok "$(xcodebuild -version | head -1), XcodeGen $(xcodegen --version | awk '{print $NF}')"

# ---------------------------------------------------------------- source
step "Getting the source"
if git rev-parse --show-toplevel >/dev/null 2>&1 && [[ -f "$(git rev-parse --show-toplevel)/project.yml" ]] \
   && grep -q "^name: Vessel" "$(git rev-parse --show-toplevel)/project.yml"; then
  ROOT="$(git rev-parse --show-toplevel)"
  echo "Using this clone: $ROOT"
else
  ROOT="${VESSEL_DIR:-$HOME/vessel}"
  if [[ -d "$ROOT/.git" ]]; then
    echo "Updating $ROOT"
    git -C "$ROOT" pull --ff-only
  else
    git clone --depth 1 "$REPO_URL" "$ROOT"
  fi
fi
cd "$ROOT"
ok "Source at $ROOT"

# ---------------------------------------------------------------- signing
step "Finding your signing team"
# The team id is the OU of the Apple Development certificate Xcode created
# when you signed in. The name in parentheses in the certificate's title is
# a personal identifier, not the team, so it's read from the subject instead.
CERT="$(security find-certificate -c "Apple Development" -p 2>/dev/null || true)"
if [[ -z "$CERT" ]]; then
  die "No Apple Development certificate on this Mac.
  1. Open Xcode → Settings → Accounts and sign in with your Apple ID (free is fine).
  2. Select your Personal Team, click Manage Certificates, then + → Apple Development.
  Then run this again."
fi
TEAM="$(printf '%s\n' "$CERT" | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
        | awk -F' = ' '/organizationalUnitName/ { print $2; exit }')"
[[ -n "$TEAM" ]] || die "Couldn't read a team id from your Apple Development certificate."
PREFIX="${VESSEL_BUNDLE_PREFIX:-com.vessel.$(printf '%s' "$TEAM" | tr '[:upper:]' '[:lower:]')}"
ok "Team $TEAM, bundle ids under $PREFIX"

# ---------------------------------------------------------------- device
step "Looking for your iPhone"
DEVICES_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 \
  || die "Couldn't list devices. Open Xcode once so it can finish installing its components."
DEVICE_LINE="$(python3 - "$DEVICES_JSON" "${VESSEL_DEVICE:-}" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2].lower()
devices = json.load(open(path)).get("result", {}).get("devices", [])
reachable, known = [], []
for d in devices:
    hw, props, conn = d.get("hardwareProperties", {}), d.get("deviceProperties", {}), d.get("connectionProperties", {})
    # devicectl lists every simulator too; only a real iPhone or iPad will do.
    if hw.get("platform") != "iOS" or hw.get("reality") != "physical":
        continue
    name, udid, ident = props.get("name", "iPhone"), hw.get("udid", ""), d.get("identifier", "")
    if wanted and wanted not in (name.lower(), udid.lower(), ident.lower()):
        continue
    entry = (name, udid, ident, conn.get("pairingState", ""))
    # "unavailable" is a phone this Mac remembers but cannot reach right now.
    (known if conn.get("tunnelState") == "unavailable" else reachable).append(entry)
if len(reachable) > 1 and not wanted:
    print("MANY\t" + ", ".join(e[0] for e in reachable))
elif reachable:
    print("\t".join(["ONE", *reachable[0]]))
elif known:
    print("AWAY\t" + known[0][0])
PY
)"
rm -f "$DEVICES_JSON"
case "${DEVICE_LINE%%$'\t'*}" in
  ONE) IFS=$'\t' read -r _ DEVICE_NAME DEVICE_UDID DEVICE_ID PAIRING <<<"$DEVICE_LINE" ;;
  MANY) die "More than one device is connected (${DEVICE_LINE#*$'\t'}). Choose one: VESSEL_DEVICE=\"<name>\" $0" ;;
  AWAY) die "Found ${DEVICE_LINE#*$'\t'}, but it isn't connected. Plug it in (or put it on the same Wi-Fi), unlock it, and run this again." ;;
  *) die "No iPhone or iPad found. Plug it in, unlock it, tap Trust This Computer, and run this again." ;;
esac
[[ "$PAIRING" == "paired" ]] || die "$DEVICE_NAME isn't paired with this Mac yet. Unlock it and tap Trust when asked, then run this again."
ok "$DEVICE_NAME"

# ---------------------------------------------------------------- build
step "Building Vessel for $DEVICE_NAME (a few minutes the first time)"
# Generate the project with your bundle ids, then put project.yml back, so a
# clone you pull into later has no local changes to trip over.
cp project.yml project.yml.install-backup
trap 'mv -f "$ROOT/project.yml.install-backup" "$ROOT/project.yml" 2>/dev/null || true' EXIT
sed -i '' "s/com\.sachinshankar/$PREFIX/g" project.yml
xcodegen generate --quiet
mv -f project.yml.install-backup project.yml

LOG="$ROOT/build/install.log"; mkdir -p "$ROOT/build"
if ! xcodebuild -project Vessel.xcodeproj -scheme Vessel -configuration Release \
      -destination "id=$DEVICE_UDID" -derivedDataPath build/install \
      -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
      build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | sort -u | head -10 >&2
  if grep -q "Developer Mode" "$LOG"; then
    die "Turn on Developer Mode on $DEVICE_NAME: Settings → Privacy & Security → Developer Mode, then restart it."
  fi
  if grep -qiE "No Account|not signed in|No profiles" "$LOG"; then
    die "Xcode couldn't create a signing profile. Open Xcode → Settings → Accounts, make sure your Apple ID is signed in, and try again."
  fi
  die "The build failed. The full log is at $LOG"
fi
APP="$(find build/install/Build/Products/Release-iphoneos -maxdepth 1 -name 'Vessel.app' | head -1)"
[[ -d "$APP" ]] || die "Built, but couldn't find Vessel.app (see $LOG)."
ok "Built and signed"

# ---------------------------------------------------------------- install
step "Installing on $DEVICE_NAME"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >/dev/null
ok "Vessel is on $DEVICE_NAME"

cat <<EOF

  One last step, the first time only:
    On $DEVICE_NAME, open Settings → General → VPN & Device Management,
    tap your Apple ID under Developer App, then tap Trust.

  Apple Watch: open the Watch app on your iPhone and install Vessel
  from Available Apps.

  With a free Apple ID, iOS stops opening the app after 7 days. Your diary
  is kept; run this command again to renew it for another week.

  How to use Vessel: https://shankar-sachin.github.io/vessel/wiki/
EOF
