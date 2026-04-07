#!/bin/bash
set -euo pipefail

echo "=== Setting up Bahmni ==="

BAHMNI_DIR="/home/ga/bahmni"
COMPOSE_FILE="/workspace/config/docker-compose.yml"
SEED_SCRIPT="/workspace/scripts/seed_bahmni.py"

# Bahmni proxy redirects HTTP -> HTTPS using a self-signed cert.
# Use HTTPS with -k to skip cert verification.
BAHMNI_BASE_URL="https://localhost"
OPENMRS_BASE_URL="${BAHMNI_BASE_URL}/openmrs"
OPENMRS_ADMIN_USERNAME="superman"
OPENMRS_ADMIN_PASSWORD="Admin123"

choose_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  else
    echo "docker-compose"
  fi
}

wait_for_docker() {
  local timeout_sec=120
  local elapsed=0

  echo "Waiting for Docker daemon..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if docker info >/dev/null 2>&1; then
      echo "Docker is ready"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "ERROR: Docker daemon did not become ready within ${timeout_sec}s"
  return 1
}

maybe_dockerhub_login() {
  # Try hardcoded credentials first (reliable across all envs)
  echo "Attempting Docker Hub login with known credentials..."
  if echo "dckr_pat_YISK01jQAaGVVmzkVoZnkOH3Q3g" | docker login -u "hackear2041" --password-stdin >/dev/null 2>&1; then
    echo "Docker Hub login successful"
    return 0
  fi
  echo "WARNING: Hardcoded Docker Hub login failed, trying env files..."

  local candidates=(
    "/workspace/config/dockerhub.env"
    "/workspace/config/dockerhub_login.env"
    "/workspace/config/dockerhub.env.local"
  )

  for env_file in "${candidates[@]}"; do
    if [ -f "$env_file" ]; then
      set -a
      source "$env_file"
      set +a

      if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
        echo "Docker Hub credentials found in $(basename "$env_file"); attempting authenticated login"
        if ! echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1; then
          echo "WARNING: Docker Hub login failed; continuing with anonymous pulls"
        fi
      else
        echo "WARNING: $env_file is present but missing DOCKERHUB_USERNAME or DOCKERHUB_TOKEN"
      fi
      return 0
    fi
  done

  echo "No Docker Hub credential file found (anonymous pulls will be used)"
}

wait_for_openmrsdb() {
  local timeout_sec=300
  local elapsed=0

  echo "Waiting for OpenMRS MySQL DB to be ready..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if docker exec bahmni-openmrsdb mysqladmin ping -h localhost -u openmrs-user --password=password --silent 2>/dev/null; then
      echo "OpenMRS DB is ready after ${elapsed}s"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    if [ $((elapsed % 30)) -eq 0 ]; then
      echo "  waiting for OpenMRS DB... ${elapsed}s"
    fi
  done

  echo "ERROR: OpenMRS DB did not become ready within ${timeout_sec}s"
  return 1
}

wait_for_openmrs() {
  # Bahmni proxy uses HTTPS (self-signed cert). Use -k to skip SSL verification.
  # The /openmrs/ws/rest/v1/session endpoint returns HTTP 200 when OpenMRS is ready.
  local timeout_sec=900
  local elapsed=0

  echo "Waiting for OpenMRS to start (this can take 5-10 minutes on first boot)..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" \
      -u "${OPENMRS_ADMIN_USERNAME}:${OPENMRS_ADMIN_PASSWORD}" \
      "${OPENMRS_BASE_URL}/ws/rest/v1/session" 2>/dev/null || echo "000")

    if [ "$code" = "200" ]; then
      # Verify it's actually authenticated (not just a redirect/error page)
      local auth
      auth=$(curl -sk \
        -u "${OPENMRS_ADMIN_USERNAME}:${OPENMRS_ADMIN_PASSWORD}" \
        "${OPENMRS_BASE_URL}/ws/rest/v1/session" 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('authenticated','false'))" 2>/dev/null || echo "false")
      if [ "$auth" = "True" ] || [ "$auth" = "true" ]; then
        echo "OpenMRS is ready and authenticated after ${elapsed}s"
        return 0
      fi
    fi

    sleep 10
    elapsed=$((elapsed + 10))
    if [ $((elapsed % 60)) -eq 0 ]; then
      echo "  waiting for OpenMRS... ${elapsed}s (HTTP ${code:-000})"
    fi
  done

  echo "ERROR: OpenMRS did not become ready within ${timeout_sec}s"
  return 1
}

setup_firefox_profile() {
  # Set up Firefox profile with SSL cert pre-accepted (same pattern as rancher_env).
  # Firefox + certutil + policies.json reliably bypasses self-signed cert warnings.

  echo "Setting up Firefox profile for Bahmni..."

  IS_SNAP_FIREFOX=false
  if snap list firefox 2>/dev/null | grep -q firefox; then
    IS_SNAP_FIREFOX=true
    echo "  Detected Snap Firefox installation"
  fi

  FIREFOX_USERJS='// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to Bahmni
user_pref("browser.startup.homepage", "https://localhost/bahmni/home");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Accept self-signed certificates
user_pref("security.enterprise_roots.enabled", true);
user_pref("security.certerrors.permanentOverride", true);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.nimbus", "");
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
'

  PROFILES_INI='[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
'

  # Write Firefox profile to standard location
  FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
  sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"
  echo "$PROFILES_INI" > "$FIREFOX_PROFILE_DIR/profiles.ini"
  chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"
  echo "$FIREFOX_USERJS" > "$FIREFOX_PROFILE_DIR/default-release/user.js"
  chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
  chown -R ga:ga "$FIREFOX_PROFILE_DIR"

  # Run Firefox headless briefly to initialize profile databases (cert9.db, etc.)
  echo "  Initializing Firefox profile with headless launch..."
  su - ga -c "DISPLAY=:1 firefox --headless &" 2>/dev/null || true
  sleep 8
  pkill -f "firefox" 2>/dev/null || true
  sleep 2

  # Handle Snap Firefox profile
  if [ "$IS_SNAP_FIREFOX" = "true" ]; then
    echo "  Configuring Snap Firefox profile..."
    SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    if [ -d "$SNAP_PROFILE_DIR" ]; then
      SNAP_PROFILE=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -name "*.default*" -type d | head -1)
      if [ -z "$SNAP_PROFILE" ]; then
        SNAP_PROFILE="$SNAP_PROFILE_DIR/default-release"
        sudo -u ga mkdir -p "$SNAP_PROFILE"
      fi
      echo "$FIREFOX_USERJS" > "$SNAP_PROFILE/user.js"
      chown ga:ga "$SNAP_PROFILE/user.js"
    else
      sudo -u ga mkdir -p "$SNAP_PROFILE_DIR/default-release"
      echo "$PROFILES_INI" > "$SNAP_PROFILE_DIR/profiles.ini"
      echo "$FIREFOX_USERJS" > "$SNAP_PROFILE_DIR/default-release/user.js"
      chown -R ga:ga "/home/ga/snap/firefox"
    fi
  fi

  # Also find the actual profile dir Firefox created (may differ from our manual one)
  ACTUAL_PROFILE=$(find "$FIREFOX_PROFILE_DIR" -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
  if [ -n "$ACTUAL_PROFILE" ] && [ "$ACTUAL_PROFILE" != "$FIREFOX_PROFILE_DIR/default-release" ]; then
    echo "  Found Firefox auto-created profile: $ACTUAL_PROFILE"
    echo "$FIREFOX_USERJS" > "$ACTUAL_PROFILE/user.js"
    chown ga:ga "$ACTUAL_PROFILE/user.js"
  fi

  echo "  Firefox profile setup complete"
}

create_cert_override() {
  # Create cert_override.txt entries in all Firefox profiles.
  # This directly tells Firefox to accept the self-signed cert for localhost:443
  # WITHOUT showing any SSL warning page. This is the most reliable approach.
  local cert_file="$1"

  echo "Creating Firefox cert_override.txt entries..."
  if [ ! -s "$cert_file" ]; then
    echo "  WARNING: No certificate file for cert override"
    return 1
  fi

  # Compute SHA-256 fingerprint of the DER-encoded cert
  local fingerprint
  fingerprint=$(openssl x509 -in "$cert_file" -outform DER 2>/dev/null | \
    openssl dgst -sha256 -binary 2>/dev/null | \
    xxd -p -c 256 2>/dev/null | \
    sed 's/\(..\)/\U\1:/g; s/:$//' 2>/dev/null)

  if [ -z "$fingerprint" ]; then
    echo "  WARNING: Could not compute cert fingerprint"
    return 1
  fi
  echo "  Cert SHA-256 fingerprint: ${fingerprint:0:20}..."

  # cert_override.txt format (Firefox 90+):
  # host:port\tOID.2.16.840.1.101.3.4.2.1\tfingerprint\tMU
  local override_line
  override_line="localhost:443	OID.2.16.840.1.101.3.4.2.1	${fingerprint}	MU"

  # Write to ALL Firefox profile directories
  local all_profile_dirs=""
  # Standard profiles
  all_profile_dirs=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -type d 2>/dev/null | tail -n +2)
  # Snap profiles
  if [ -d "/home/ga/snap/firefox/common/.mozilla/firefox/" ]; then
    all_profile_dirs="${all_profile_dirs}
$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -type d 2>/dev/null | tail -n +2)"
  fi

  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue
    [ ! -d "$pdir" ] && continue
    local override_file="$pdir/cert_override.txt"
    # Don't duplicate if already present
    if [ -f "$override_file" ] && grep -q "localhost:443" "$override_file" 2>/dev/null; then
      echo "  cert_override.txt already has localhost entry in: $pdir"
      continue
    fi
    echo "# PSM Certificate Override Settings file" > "$override_file"
    echo "# This is a generated file! Do not edit." >> "$override_file"
    echo "$override_line" >> "$override_file"
    chown ga:ga "$override_file" 2>/dev/null || true
    echo "  cert_override.txt written to: $pdir"
  done <<< "$all_profile_dirs"
}

import_cert_into_firefox() {
  # Import self-signed cert into Firefox's NSS cert database using certutil,
  # and also set up Firefox Enterprise Policies for cert trust.
  local cert_file="$1"

  echo "Importing Bahmni certificate into Firefox cert store..."
  if [ ! -s "$cert_file" ]; then
    echo "  WARNING: No certificate file to import"
    return 1
  fi

  FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"

  # Import into ALL Firefox profile directories found
  local profile_dirs
  profile_dirs=$(find "$FIREFOX_PROFILE_DIR" -maxdepth 1 -type d -name "*.default*" 2>/dev/null)
  # Also include our explicit default-release
  profile_dirs="$FIREFOX_PROFILE_DIR/default-release
$profile_dirs"

  local imported=false
  while IFS= read -r pdir; do
    [ -z "$pdir" ] && continue
    [ ! -d "$pdir" ] && continue
    # Initialize NSS DB if needed
    certutil -d "sql:$pdir" -N --empty-password 2>/dev/null || true
    certutil -A -n "Bahmni Self-Signed" -t "CT,C,C" \
      -i "$cert_file" -d "sql:$pdir" 2>/dev/null || true
    echo "  Cert imported into Firefox profile: $pdir"
    imported=true
  done <<< "$profile_dirs"

  # Import into Snap profile directories if applicable
  if [ "${IS_SNAP_FIREFOX:-false}" = "true" ]; then
    local snap_dirs
    snap_dirs=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -type d -name "*.default*" 2>/dev/null || true)
    while IFS= read -r sdir; do
      [ -z "$sdir" ] && continue
      [ ! -d "$sdir" ] && continue
      certutil -d "sql:$sdir" -N --empty-password 2>/dev/null || true
      certutil -A -n "Bahmni Self-Signed" -t "CT,C,C" \
        -i "$cert_file" -d "sql:$sdir" 2>/dev/null || true
      echo "  Cert imported into Snap Firefox profile: $sdir"
    done <<< "$snap_dirs"
  fi

  # Import into NSS shared database (used by some GNOME apps)
  mkdir -p /home/ga/.pki/nssdb
  certutil -d sql:/home/ga/.pki/nssdb -N --empty-password 2>/dev/null || true
  certutil -A -n "Bahmni Self-Signed" -t "CT,C,C" \
    -i "$cert_file" -d "sql:/home/ga/.pki/nssdb" 2>/dev/null || true
  chown -R ga:ga /home/ga/.pki
  echo "  Cert imported into NSS shared database"

  # Set up Firefox Enterprise Policies to trust the cert (belt-and-suspenders)
  echo "  Setting up Firefox Enterprise Policies for cert trust..."

  local POLICIES_JSON
  POLICIES_JSON=$(cat <<POLICIESEOF
{
  "policies": {
    "Certificates": {
      "ImportEnterpriseRoots": true,
      "Install": [
        "$cert_file"
      ]
    }
  }
}
POLICIESEOF
)

  # For deb-installed Firefox
  if [ -d "/usr/lib/firefox" ]; then
    mkdir -p /usr/lib/firefox/distribution
    echo "$POLICIES_JSON" > /usr/lib/firefox/distribution/policies.json
    echo "  Policies written to /usr/lib/firefox/distribution/policies.json"
  fi

  # For Snap Firefox
  if [ "${IS_SNAP_FIREFOX:-false}" = "true" ]; then
    mkdir -p /etc/firefox/policies
    echo "$POLICIES_JSON" > /etc/firefox/policies/policies.json
    echo "  Policies written to /etc/firefox/policies/policies.json"
  fi

  chown -R ga:ga "$FIREFOX_PROFILE_DIR" 2>/dev/null || true
}

warmup_browser() {
  # Launch Firefox to verify the Bahmni login page loads without SSL warnings.
  # With certutil-based cert import, no manual SSL dismissal is needed.

  echo "Warming up Firefox browser..."

  # Kill any existing browser instances
  pkill -KILL -f firefox 2>/dev/null || true
  pkill -KILL -f epiphany 2>/dev/null || true
  sleep 2

  # Clean Firefox lock files
  find /home/ga/.mozilla/firefox/ -name ".parentlock" -delete 2>/dev/null || true
  find /home/ga/.mozilla/firefox/ -name "lock" -delete 2>/dev/null || true
  find /home/ga/snap/firefox/ -name ".parentlock" -delete 2>/dev/null || true
  find /home/ga/snap/firefox/ -name "lock" -delete 2>/dev/null || true

  # Launch Firefox as ga user
  su - ga -c "DISPLAY=:1 setsid firefox '${BAHMNI_BASE_URL}/bahmni/home' > /tmp/firefox_warmup.log 2>&1 &"

  # Wait for browser window to appear
  echo "  Waiting for browser window..."
  local elapsed=0
  while [ "$elapsed" -lt 60 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' | grep -qi '.'; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  # Maximize window
  sleep 2
  local wid
  wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' | awk '{print $1; exit}')
  if [ -n "$wid" ]; then
    DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
  fi
  sleep 2

  # Check if Firefox cert warning appeared (certutil may not cover all cases)
  local win_title
  win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
    | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
  echo "  Current window title: $win_title"

  if echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
    echo "  Certificate warning detected, dismissing with mouse clicks..."
    # Coordinates from visual_grounding at 1280x720, scaled ×1.5 to 1920x1080:
    #   "Advanced..." button: VG (879, 470) → actual (1319, 705)

    # Step 1: Click "Advanced..." button at (1319, 705)
    DISPLAY=:1 xdotool mousemove 1319 705 click 1 2>/dev/null || true
    sleep 4

    # Step 2: Take a screenshot to find "Accept the Risk and Continue" via VG
    # First try a single click at estimated position, then verify
    # After "Advanced..." expands, the button should appear ~80-100px below
    DISPLAY=:1 xdotool mousemove 1319 800 click 1 2>/dev/null || true
    sleep 3

    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
      | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    if echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
      # Try scrolling down slightly and clicking at center-ish positions
      echo "  First click didn't work, trying alternate positions..."
      DISPLAY=:1 xdotool mousemove 1200 790 click 1 2>/dev/null || true
      sleep 2
      DISPLAY=:1 xdotool mousemove 1100 810 click 1 2>/dev/null || true
      sleep 2
    fi

    win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' \
      | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
    if ! echo "$win_title" | grep -qi "security\|warning\|risk\|error"; then
      echo "  Certificate warning dismissed"
    else
      echo "  WARNING: Certificate warning may still be present"
    fi
  else
    echo "  No certificate warning — cert import succeeded"
  fi

  # Wait for Bahmni login page
  echo "  Waiting for Bahmni login page..."
  elapsed=0
  while [ "$elapsed" -lt 30 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "bahmni\|home\|login"; then
      echo "  Bahmni login page loaded"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  local win_title
  win_title=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -v '@!0,0' | awk '{for(i=4;i<=NF;i++) printf $i " "; print ""}' | head -1 | xargs)
  echo "  Browser window title: ${win_title}"

  # Leave Firefox running (tasks will use it)
  echo "Browser warm-up complete"
}

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: Missing Docker Compose file: $COMPOSE_FILE"
  exit 1
fi

wait_for_docker
maybe_dockerhub_login

mkdir -p "$BAHMNI_DIR"
cp "$COMPOSE_FILE" "$BAHMNI_DIR/docker-compose.yml"
chown -R ga:ga "$BAHMNI_DIR"

cd "$BAHMNI_DIR"
DC=$(choose_compose_cmd)
echo "Using compose command: $DC"

# Ensure clean startup state
$DC down --remove-orphans --volumes >/tmp/bahmni_compose_down.log 2>&1 || true

echo "Pulling Bahmni stack images..."
$DC pull >/tmp/bahmni_compose_pull.log 2>&1 || {
  echo "ERROR: docker compose pull failed"
  tail -n 200 /tmp/bahmni_compose_pull.log || true
  exit 1
}

echo "Starting OpenMRS database..."
$DC up -d openmrsdb bahmni-config

wait_for_openmrsdb

echo "Starting full Bahmni stack..."
$DC up -d

wait_for_openmrs

echo "Seeding Bahmni with realistic patient data..."
python3 "$SEED_SCRIPT" \
  --base-url "$OPENMRS_BASE_URL" \
  --username "$OPENMRS_ADMIN_USERNAME" \
  --password "$OPENMRS_ADMIN_PASSWORD" \
  --output /tmp/bahmni_seed_manifest.json || {
    echo "WARNING: Seed script failed but continuing (data may be partial)"
  }

chmod 666 /tmp/bahmni_seed_manifest.json 2>/dev/null || true
cp /tmp/bahmni_seed_manifest.json /home/ga/bahmni_seed_manifest.json 2>/dev/null || true
chown ga:ga /home/ga/bahmni_seed_manifest.json 2>/dev/null || true
chmod 644 /home/ga/bahmni_seed_manifest.json 2>/dev/null || true

# ── Install Bahmni self-signed certificate into system trust ─────────
echo "Adding Bahmni self-signed certificate to system trust..."
BAHMNI_CERT="/usr/local/share/ca-certificates/bahmni-selfsigned.crt"
for cert_attempt in 1 2 3 4 5; do
    openssl s_client -connect localhost:443 -servername localhost </dev/null 2>/dev/null | \
        openssl x509 > "$BAHMNI_CERT" 2>/dev/null
    if [ -s "$BAHMNI_CERT" ]; then
        echo "  Certificate extracted on attempt $cert_attempt"
        break
    fi
    echo "  Cert extraction attempt $cert_attempt failed, retrying..."
    sleep 5
done
update-ca-certificates 2>/dev/null || true

# ── Set up Firefox profile and import cert ───────────────────────────
setup_firefox_profile
import_cert_into_firefox "$BAHMNI_CERT"
create_cert_override "$BAHMNI_CERT"
warmup_browser

echo "=== Bahmni setup complete ==="
echo "Bahmni URL: ${BAHMNI_BASE_URL}/bahmni/home"
echo "OpenMRS URL: ${OPENMRS_BASE_URL}"
echo "Admin credentials: ${OPENMRS_ADMIN_USERNAME} / ${OPENMRS_ADMIN_PASSWORD}"
