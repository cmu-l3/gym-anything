#!/bin/bash
set -euo pipefail

echo "=== Setting up Mattermost ==="

MATTERMOST_DIR="/home/ga/mattermost"
COMPOSE_FILE="/workspace/config/docker-compose.yml"
RELEASE_DATA_FILE="/workspace/assets/mattermost_releases_github.json"
SEED_SCRIPT="/workspace/scripts/seed_mattermost.py"
SEED_MANIFEST_VM="/tmp/mattermost_seed_manifest.json"

MATTERMOST_BASE_URL="http://localhost:8065"
MATTERMOST_ADMIN_USERNAME="admin"
MATTERMOST_ADMIN_PASSWORD="Admin1234!"
MATTERMOST_ADMIN_EMAIL="admin@mattermost.local"
MATTERMOST_AGENT_USERNAME="agent.user"
MATTERMOST_AGENT_PASSWORD="AgentPass123!"
MATTERMOST_AGENT_EMAIL="agent.user@mattermost.local"
MATTERMOST_TEAM_NAME="main-team"

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

wait_for_postgres() {
  local timeout_sec=180
  local elapsed=0

  echo "Waiting for PostgreSQL to accept connections..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if docker exec mm-postgres pg_isready -U mmuser -d mattermost >/dev/null 2>&1; then
      echo "PostgreSQL is ready"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  echo "ERROR: PostgreSQL was not ready within ${timeout_sec}s"
  return 1
}

wait_for_mattermost_http() {
  local timeout_sec=600
  local elapsed=0

  echo "Waiting for Mattermost HTTP readiness at ${MATTERMOST_BASE_URL}..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${MATTERMOST_BASE_URL}/api/v4/system/ping" 2>/dev/null || true)

    if [ "$code" = "200" ]; then
      echo "Mattermost responded with HTTP ${code} after ${elapsed}s"
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
    if [ $((elapsed % 30)) -eq 0 ]; then
      echo "  waiting... ${elapsed}s (HTTP ${code:-000})"
    fi
  done

  echo "ERROR: Mattermost did not become ready within ${timeout_sec}s"
  return 1
}

setup_firefox_profile() {
  echo "Setting up Firefox profile for deterministic startup"

  local profile_root="/home/ga/.mozilla/firefox"
  local profile_dir="${profile_root}/default.profile"

  sudo -u ga mkdir -p "$profile_dir"

  cat > "${profile_root}/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default
IsRelative=1
Path=default.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

  cat > "${profile_dir}/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.vpn_promo.enabled", false);
USERJS

  chown -R ga:ga "$profile_root"

  rm -rf "${profile_dir}/lock" \
    "${profile_dir}/.parentlock" \
    "${profile_dir}/parent.lock" \
    "${profile_dir}/singletonLock" \
    "${profile_dir}/singletonCookie" \
    "${profile_dir}/singletonSocket" \
    2>/dev/null || true

  pkill -TERM -f firefox 2>/dev/null || true
  sleep 2
  pkill -KILL -f firefox 2>/dev/null || true

  rm -rf "${profile_dir}/lock" \
    "${profile_dir}/.parentlock" \
    "${profile_dir}/parent.lock" \
    "${profile_dir}/singletonLock" \
    "${profile_dir}/singletonCookie" \
    "${profile_dir}/singletonSocket" \
    2>/dev/null || true
}

# Validate required files
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: Missing Docker Compose file: $COMPOSE_FILE"
  exit 1
fi

if [ ! -f "$RELEASE_DATA_FILE" ]; then
  echo "ERROR: Missing release dataset: $RELEASE_DATA_FILE"
  exit 1
fi

if [ ! -f "$SEED_SCRIPT" ]; then
  echo "ERROR: Missing seed script: $SEED_SCRIPT"
  exit 1
fi

wait_for_docker

mkdir -p "$MATTERMOST_DIR"
cp "$COMPOSE_FILE" "$MATTERMOST_DIR/docker-compose.yml"
chown -R ga:ga "$MATTERMOST_DIR"

cd "$MATTERMOST_DIR"
DC=$(choose_compose_cmd)

echo "Using compose command: $DC"

# Ensure deterministic startup state
$DC down --remove-orphans --volumes >/tmp/mattermost_compose_down.log 2>&1 || true

echo "Starting PostgreSQL..."
$DC up -d postgres

wait_for_postgres

echo "Starting Mattermost..."
$DC up -d mattermost

wait_for_mattermost_http

echo "Seeding Mattermost workspace with real release data..."
python3 "$SEED_SCRIPT" \
  --base-url "$MATTERMOST_BASE_URL" \
  --admin-username "$MATTERMOST_ADMIN_USERNAME" \
  --admin-password "$MATTERMOST_ADMIN_PASSWORD" \
  --admin-email "$MATTERMOST_ADMIN_EMAIL" \
  --agent-username "$MATTERMOST_AGENT_USERNAME" \
  --agent-password "$MATTERMOST_AGENT_PASSWORD" \
  --agent-email "$MATTERMOST_AGENT_EMAIL" \
  --team-name "$MATTERMOST_TEAM_NAME" \
  --channel-name "release-updates" \
  --release-data "$RELEASE_DATA_FILE" \
  --output "$SEED_MANIFEST_VM"

chmod 666 "$SEED_MANIFEST_VM" 2>/dev/null || true
cp "$SEED_MANIFEST_VM" /home/ga/mattermost_seed_manifest.json 2>/dev/null || true
chown ga:ga /home/ga/mattermost_seed_manifest.json 2>/dev/null || true
chmod 644 /home/ga/mattermost_seed_manifest.json 2>/dev/null || true

setup_firefox_profile

# Launch Firefox with Mattermost login page
echo "Re-verifying Mattermost is responsive before launching Firefox..."
for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "${MATTERMOST_BASE_URL}/api/v4/system/ping" 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
        echo "Mattermost web service ready"
        break
    fi
    sleep 2
done

echo "Launching browser with Mattermost login page..."
if command -v epiphany-browser >/dev/null 2>&1; then
  BROWSER_CMD="epiphany-browser"
elif command -v epiphany >/dev/null 2>&1; then
  BROWSER_CMD="epiphany"
else
  BROWSER_CMD="firefox"
fi
echo "Using browser: $BROWSER_CMD"

if [ "$BROWSER_CMD" = "firefox" ]; then
  su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${MATTERMOST_BASE_URL}/login' > /tmp/firefox_mattermost.log 2>&1 &"
else
  su - ga -c "DISPLAY=:1 $BROWSER_CMD '${MATTERMOST_BASE_URL}/login' > /tmp/firefox_mattermost.log 2>&1 &"
fi

# Wait for browser window
FF_STARTED=false
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "epiphany\|web\|firefox\|mozilla\|mattermost"; then
        FF_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FF_STARTED" = "true" ]; then
    sleep 1
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== Mattermost setup complete ==="
echo "Mattermost URL: ${MATTERMOST_BASE_URL}"
echo "Admin credentials: ${MATTERMOST_ADMIN_USERNAME} / ${MATTERMOST_ADMIN_PASSWORD}"
echo "Agent credentials: ${MATTERMOST_AGENT_USERNAME} / ${MATTERMOST_AGENT_PASSWORD}"
echo "Team: ${MATTERMOST_TEAM_NAME}"
echo "Seed manifest: ${SEED_MANIFEST_VM}"
