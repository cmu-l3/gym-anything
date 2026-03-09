#!/bin/bash
set -e

echo "=== Setting up OpenMaint ==="

OPENMAINT_DIR="/home/ga/openmaint"
OPENMAINT_URL="http://localhost:8090/cmdbuild/ui/"
DOCKER_AUTH_FILE="/workspace/config/dockerhub_login.env"

mkdir -p "$OPENMAINT_DIR"
cp /workspace/config/docker-compose.yml "$OPENMAINT_DIR/docker-compose.yml"
chown -R ga:ga "$OPENMAINT_DIR"

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

wait_for_http() {
  local url="$1"
  local timeout="${2:-420}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
      echo "OpenMaint reachable at $url after ${elapsed}s (HTTP $code)"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "ERROR: Timeout waiting for OpenMaint at $url"
  return 1
}

wait_for_health() {
  local container="$1"
  local timeout="${2:-420}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    local status
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "missing")
    if [ "$status" = "healthy" ]; then
      echo "Container $container healthy after ${elapsed}s"
      return 0
    fi
    if [ "$status" = "unhealthy" ]; then
      echo "Container $container became unhealthy"
      docker logs --tail 60 "$container" || true
      return 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "ERROR: Timeout waiting for $container health"
  docker logs --tail 60 "$container" || true
  return 1
}

cd "$OPENMAINT_DIR"

# Optional Docker Hub authentication to avoid unauthenticated pull limits.
if [ -f "$DOCKER_AUTH_FILE" ]; then
  # shellcheck source=/dev/null
  source "$DOCKER_AUTH_FILE"
  if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]; then
    echo "Docker Hub auth file detected; attempting docker login..."
    if ! echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1; then
      echo "WARNING: Docker login failed; continuing without authenticated pulls"
    fi
  else
    echo "WARNING: $DOCKER_AUTH_FILE exists but missing DOCKERHUB_USERNAME or DOCKERHUB_TOKEN"
  fi
fi

$DC up -d
$DC ps

wait_for_health openmaint_db 240
wait_for_health openmaint_app 420
wait_for_http "$OPENMAINT_URL" 420

echo "Configuring Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-openmaint"

cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default-openmaint
IsRelative=1
Path=default-openmaint
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$FIREFOX_PROFILE_DIR/default-openmaint/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "http://localhost:8090/cmdbuild/ui/");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.newtabpage.enabled", false);
USERJS

chown -R ga:ga "$FIREFOX_PROFILE_DIR"

cat > /usr/local/bin/openmaint-db-query << 'EOQ'
#!/bin/bash
docker exec openmaint_db psql -U postgres -d openmaint -At -c "$1"
EOQ
chmod +x /usr/local/bin/openmaint-db-query

mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/OpenMaint.desktop << 'DESKTOP'
[Desktop Entry]
Name=OpenMaint
Comment=OpenMaint Facility Management
Exec=firefox http://localhost:8090/cmdbuild/ui/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOP
chown ga:ga /home/ga/Desktop/OpenMaint.desktop
chmod +x /home/ga/Desktop/OpenMaint.desktop

pkill -f firefox || true
sleep 1

echo "Launching Firefox with OpenMaint..."
su - ga -c "DISPLAY=:1 firefox '$OPENMAINT_URL' > /tmp/firefox_openmaint.log 2>&1 &"

sleep 6
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla\|openmaint' | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
  DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== OpenMaint setup complete ==="
echo "OpenMaint URL: $OPENMAINT_URL"
echo "OpenMaint credentials: admin / admin"
