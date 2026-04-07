#!/bin/bash
set -euo pipefail

echo "=== Setting up Rocket.Chat ==="

ROCKETCHAT_DIR="/home/ga/rocketchat"
COMPOSE_FILE="/workspace/config/docker-compose.yml"
RELEASE_DATA_FILE="/workspace/assets/rocketchat_releases_github_api_2026-02-16.json"
SEED_SCRIPT="/workspace/scripts/seed_rocket_chat.py"
SEED_MANIFEST_VM="/tmp/rocket_chat_seed_manifest.json"

ROCKETCHAT_BASE_URL="http://localhost:3000"
ROCKETCHAT_ADMIN_USERNAME="admin"
ROCKETCHAT_ADMIN_PASSWORD="Admin1234!"
ROCKETCHAT_AGENT_USERNAME="agent.user"
ROCKETCHAT_AGENT_PASSWORD="AgentPass123!"

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
  local candidates=(
    "/workspace/config/dockerhub.env"
    "/workspace/config/dockerhub_login.env"
    "/workspace/config/dockerhub.env.local"
  )

  for env_file in "${candidates[@]}"; do
    if [ -f "$env_file" ]; then
      # shellcheck disable=SC1090
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

  echo "No Docker Hub credential file found under /workspace/config (anonymous pulls will be used)"
}

wait_for_mongodb() {
  local timeout_sec=180
  local elapsed=0

  echo "Waiting for MongoDB container to accept commands..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    if docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/?directConnection=true" --eval "db.adminCommand({ ping: 1 }).ok" >/dev/null 2>&1; then
      echo "MongoDB is ready"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  echo "ERROR: MongoDB was not ready within ${timeout_sec}s"
  return 1
}

init_replica_set() {
  local check_js='try { const s = rs.status(); if (s.ok === 1) { quit(0); } quit(1); } catch (e) { quit(2); }'
  local init_js='rs.initiate({_id: "rs0", members: [{ _id: 0, host: "mongodb:27017" }]})'
  local primary_js='try { const s = rs.status(); const isPrimary = s.members.some(m => m.stateStr === "PRIMARY"); if (isPrimary) { quit(0); } quit(1); } catch (e) { quit(1); }'

  if docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/?directConnection=true" --eval "$check_js" >/dev/null 2>&1; then
    echo "MongoDB replica set already initialized"
  else
    echo "Initializing MongoDB replica set rs0"
    docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/?directConnection=true" --eval "$init_js" >/tmp/rocket_chat_rs_init.log 2>&1 || true
    cat /tmp/rocket_chat_rs_init.log || true
  fi

  echo "Waiting for MongoDB PRIMARY state..."
  for _ in $(seq 1 60); do
    if docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/?directConnection=true" --eval "$primary_js" >/dev/null 2>&1; then
      echo "MongoDB replica set is PRIMARY"
      return 0
    fi
    sleep 2
  done

  echo "ERROR: MongoDB replica set did not become PRIMARY"
  return 1
}

wait_for_rocketchat_http() {
  local timeout_sec=600
  local elapsed=0

  echo "Waiting for Rocket.Chat HTTP readiness at ${ROCKETCHAT_BASE_URL}..."
  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "${ROCKETCHAT_BASE_URL}/api/info" 2>/dev/null || true)

    if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "403" ]; then
      echo "Rocket.Chat responded with HTTP ${code} after ${elapsed}s"
      return 0
    fi

    sleep 5
    elapsed=$((elapsed + 5))
    if [ $((elapsed % 30)) -eq 0 ]; then
      echo "  waiting... ${elapsed}s (HTTP ${code:-000})"
    fi
  done

  echo "ERROR: Rocket.Chat did not become ready within ${timeout_sec}s"
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
maybe_dockerhub_login

mkdir -p "$ROCKETCHAT_DIR"
cp "$COMPOSE_FILE" "$ROCKETCHAT_DIR/docker-compose.yml"
chown -R ga:ga "$ROCKETCHAT_DIR"

cd "$ROCKETCHAT_DIR"
DC=$(choose_compose_cmd)

echo "Using compose command: $DC"

# Ensure deterministic startup state
$DC down --remove-orphans --volumes >/tmp/rocket_chat_compose_down.log 2>&1 || true

echo "Starting MongoDB and NATS..."
$DC up -d mongodb nats

wait_for_mongodb
init_replica_set

echo "Starting Rocket.Chat..."
$DC up -d rocketchat

wait_for_rocketchat_http

echo "Seeding Rocket.Chat workspace with real release data..."
python3 "$SEED_SCRIPT" \
  --base-url "$ROCKETCHAT_BASE_URL" \
  --admin-username "$ROCKETCHAT_ADMIN_USERNAME" \
  --admin-password "$ROCKETCHAT_ADMIN_PASSWORD" \
  --agent-username "$ROCKETCHAT_AGENT_USERNAME" \
  --agent-password "$ROCKETCHAT_AGENT_PASSWORD" \
  --agent-name "Agent User" \
  --agent-email "agent.user@rocketchat.local" \
  --channel-name "release-updates" \
  --release-data "$RELEASE_DATA_FILE" \
  --output "$SEED_MANIFEST_VM"

chmod 666 "$SEED_MANIFEST_VM" 2>/dev/null || true
cp "$SEED_MANIFEST_VM" /home/ga/rocket_chat_seed_manifest.json 2>/dev/null || true
chown ga:ga /home/ga/rocket_chat_seed_manifest.json 2>/dev/null || true
chmod 644 /home/ga/rocket_chat_seed_manifest.json 2>/dev/null || true

# The OVERWRITE_SETTING_Show_Setup_Wizard env var does not always prevent the
# setup wizard from appearing on first admin login.  Explicitly mark it
# completed via the REST API so that login always goes to the main UI.
echo "Marking setup wizard completed via REST API..."
_RC_LOGIN_JSON=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_ADMIN_USERNAME}\",\"password\":\"${ROCKETCHAT_ADMIN_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null || true)

_RC_TOKEN=$(echo "$_RC_LOGIN_JSON" | jq -r '.data.authToken // empty' 2>/dev/null || true)
_RC_USERID=$(echo "$_RC_LOGIN_JSON" | jq -r '.data.userId // empty' 2>/dev/null || true)

if [ -n "$_RC_TOKEN" ] && [ -n "$_RC_USERID" ]; then
  curl -sS -X POST \
    -H "X-Auth-Token: $_RC_TOKEN" \
    -H "X-User-Id: $_RC_USERID" \
    -H "Content-Type: application/json" \
    -d '{"value":"completed"}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Show_Setup_Wizard" >/dev/null 2>&1 || true

  curl -sS -X POST \
    -H "X-Auth-Token: $_RC_TOKEN" \
    -H "X-User-Id: $_RC_USERID" \
    -H "Content-Type: application/json" \
    -d '{"value":"community"}' \
    "${ROCKETCHAT_BASE_URL}/api/v1/settings/Organization_Type" >/dev/null 2>&1 || true

  echo "Setup wizard marked as completed"
else
  echo "WARNING: Could not obtain admin token to dismiss setup wizard"
fi

setup_firefox_profile

# Launch Firefox with Rocket.Chat login page
echo "Re-verifying Rocket.Chat is responsive before launching Firefox..."
for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "${ROCKETCHAT_BASE_URL}/api/info" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "403" ]; then
        echo "Rocket.Chat web service ready"
        break
    fi
    sleep 2
done

echo "Launching Firefox with Rocket.Chat login page..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus firefox '${ROCKETCHAT_BASE_URL}' > /tmp/firefox_rocketchat.log 2>&1 &"

# Wait for Firefox window
FF_STARTED=false
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|rocket"; then
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

echo "=== Rocket.Chat setup complete ==="
echo "Rocket.Chat URL: ${ROCKETCHAT_BASE_URL}"
echo "Admin credentials: ${ROCKETCHAT_ADMIN_USERNAME} / ${ROCKETCHAT_ADMIN_PASSWORD}"
echo "Agent credentials: ${ROCKETCHAT_AGENT_USERNAME} / ${ROCKETCHAT_AGENT_PASSWORD}"
echo "Seed manifest: ${SEED_MANIFEST_VM}"
