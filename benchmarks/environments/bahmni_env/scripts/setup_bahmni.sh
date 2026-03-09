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

warmup_browser() {
  # Warm-up Epiphany browser by loading Bahmni login page and dismissing the
  # self-signed SSL certificate warning.
  #
  # Epiphany does NOT persist SSL cert exceptions across restarts (no ~/.pki/nssdb).
  # Each task setup (pre_task hook) will independently dismiss the SSL warning
  # via the dismiss_ssl_warning() function in task_utils.sh.
  #
  # This warmup verifies the full browser→SSL-dismiss→login-page flow works.
  # It also pre-warms any GNOME session caches needed for Epiphany.
  #
  # Epiphany SSL dismissal coordinates (1850x1053 maximized window):
  #   1. Click "Technical information" to expand: actual (707, 706)
  #   2. Click "Accept Risk and Proceed": actual (717, 770)

  echo "Warming up Epiphany browser and verifying SSL warning dismissal..."

  local XAUTH="/run/user/1000/gdm/Xauthority"
  local elapsed=0

  # Kill any existing browser instances
  pkill -KILL -f epiphany 2>/dev/null || true
  sleep 1

  # Launch Epiphany with required env vars.
  # GDK_BACKEND=x11 is required for Epiphany to show on X11 from SSH/hooks.
  bash -c "DISPLAY=:1 XAUTHORITY=${XAUTH} GDK_BACKEND=x11 epiphany-browser '${BAHMNI_BASE_URL}/bahmni/home' > /tmp/epiphany_warmup.log 2>&1 &"

  # Wait for browser window to appear
  echo "  Waiting for browser window..."
  while [ "$elapsed" -lt 30 ]; do
    if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -v '@!0,0' | grep -qi '.'; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  # Maximize window
  sleep 1
  local wid
  wid=$(DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -v '@!0,0' | awk '{print $1; exit}')
  if [ -n "$wid" ]; then
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -ia "$wid" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
  fi
  sleep 1

  # Check if SSL warning is shown and dismiss it
  if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "Security Violation"; then
    echo "  Dismissing SSL warning..."
    local ssl_wid
    ssl_wid=$(DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -i "Security Violation" | awk '{print $1; exit}')
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -ia "$ssl_wid" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 0.5

    # Click "Technical information" to expand (actual: 707, 706 for 1850x1053 window)
    DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool mousemove --window "$ssl_wid" 707 706 click 1 2>/dev/null || true
    sleep 1.5

    # Click "Accept Risk and Proceed" (actual: 717, 770 for 1850x1053 window)
    DISPLAY=:1 XAUTHORITY="${XAUTH}" xdotool mousemove --window "$ssl_wid" 717 770 click 1 2>/dev/null || true
    sleep 5

    echo "  SSL warning dismissed"
  fi

  # Wait for Bahmni login page
  echo "  Waiting for Bahmni login page..."
  elapsed=0
  while [ "$elapsed" -lt 30 ]; do
    if DISPLAY=:1 XAUTHORITY="${XAUTH}" wmctrl -l 2>/dev/null | grep -qi "bahmni\|home"; then
      echo "  Bahmni login page loaded"
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  # Keep browser open briefly then kill (tasks will relaunch with fresh Epiphany)
  sleep 2
  pkill -KILL -f epiphany 2>/dev/null || true
  sleep 1
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

warmup_browser

echo "=== Bahmni setup complete ==="
echo "Bahmni URL: ${BAHMNI_BASE_URL}/bahmni/home"
echo "OpenMRS URL: ${OPENMRS_BASE_URL}"
echo "Admin credentials: ${OPENMRS_ADMIN_USERNAME} / ${OPENMRS_ADMIN_PASSWORD}"
