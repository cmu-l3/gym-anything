#!/bin/bash
set -e

echo "=== Setting up Vicidial ==="

VICIDIAL_DIR="/home/ga/vicidial"
VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"
DOCKER_AUTH_FILE="/workspace/config/dockerhub_login.env"

mkdir -p "$VICIDIAL_DIR"
cp /workspace/config/docker-compose.yml "$VICIDIAL_DIR/docker-compose.yml"
chown -R ga:ga "$VICIDIAL_DIR"

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

echo "Creating Vicidial ensure-running script..."
cat > /usr/local/bin/vicidial-ensure-running << 'STARTUPEOF'
#!/bin/bash
set -e

LOG_FILE="/var/log/vicidial-startup.log"
VICIDIAL_DIR="/home/ga/vicidial"
ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"
MAX_RETRIES=10
RETRY_DELAY=5

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "=== Vicidial ensure-running started ==="

# Step 1: Ensure Docker daemon is running.
for i in $(seq 1 $MAX_RETRIES); do
  if docker info >/dev/null 2>&1; then
    log "Docker daemon is running"
    break
  fi
  log "Docker not responding; attempting to start (attempt $i/$MAX_RETRIES)..."
  systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
  sleep "$RETRY_DELAY"
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    log "FATAL: Docker daemon failed to start after $MAX_RETRIES attempts"
    exit 1
  fi
done

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

# Step 2: Ensure container is running.
cd "$VICIDIAL_DIR" || {
  log "FATAL: Cannot cd to $VICIDIAL_DIR"
  exit 1
}

RUNNING=$(docker ps -q -f name=vicidial -f status=running 2>/dev/null || true)
if [ -z "$RUNNING" ]; then
  log "Vicidial container not running; starting with $DC up -d..."
  $DC up -d 2>&1 | tee -a "$LOG_FILE"
fi

for i in $(seq 1 120); do
  RUNNING=$(docker ps -q -f name=vicidial -f status=running 2>/dev/null || true)
  if [ -n "$RUNNING" ]; then
    log "Vicidial container is running after ${i}s"
    break
  fi
  sleep 1
  if [ "$i" -eq 120 ]; then
    log "ERROR: Vicidial container did not reach running state"
    docker ps -a --filter name=vicidial 2>&1 | tee -a "$LOG_FILE" || true
    exit 1
  fi
done

# Step 3: Wait for web UI.
for i in $(seq 1 240); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$ADMIN_URL" 2>/dev/null || echo "000")
  if [ "$code" = "200" ] || [ "$code" = "302" ] || [ "$code" = "401" ]; then
    log "Vicidial web UI reachable at $ADMIN_URL after ${i}s (HTTP $code)"
    exit 0
  fi
  [ $((i % 15)) -eq 0 ] && log "Still waiting for web UI... ${i}s (HTTP $code)"
  sleep 1
done

log "ERROR: Vicidial web UI not reachable at $ADMIN_URL after 240s"
docker logs --tail 200 vicidial 2>&1 | tee -a "$LOG_FILE" || true
exit 1
STARTUPEOF
chmod +x /usr/local/bin/vicidial-ensure-running

echo "Creating systemd service for Vicidial..."
cat > /etc/systemd/system/vicidial-docker.service << 'SYSTEMDEOF'
[Unit]
Description=Vicidial Docker Container
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/vicidial-ensure-running
ExecStop=/usr/bin/docker-compose -f /home/ga/vicidial/docker-compose.yml down
TimeoutStartSec=600
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

systemctl daemon-reload
systemctl enable vicidial-docker.service
systemctl start vicidial-docker.service

# Vicidial image defaults ship with an "admin" user that lacks list/lead permissions.
# Fix these once at env setup so tasks can create lists + load leads deterministically.
echo "Waiting for Vicidial MySQL to be ready..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Vicidial MySQL is ready"
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "WARNING: Vicidial MySQL did not become ready; skipping initial permission fix"
  fi
done

if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
  echo "Applying Vicidial permissions for user 6666..."
  docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE vicidial_users SET modify_lists='1', modify_leads='1', modify_campaigns='1', view_reports='1' WHERE user='6666';" \
    >/dev/null 2>&1 || true
fi

# Copy real-world lead data into the VM for tasks.
echo "Copying real lead data assets into /home/ga/Documents..."
mkdir -p /home/ga/Documents/VicidialData
cp /workspace/assets/us_senate_senators_cfm_2026-02-14.xml /home/ga/Documents/VicidialData/ 2>/dev/null || true
cp /workspace/assets/us_senators_vicidial_leads_2026-02-14.csv /home/ga/Documents/VicidialData/ 2>/dev/null || true
cp /workspace/assets/us_senators_vicidial_standard_format_list9001_2026-02-14.csv /home/ga/Documents/VicidialData/ 2>/dev/null || true
cp /workspace/assets/us_senators_vicidial_standard_format_list9001_2026-02-14.txt /home/ga/Documents/VicidialData/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/VicidialData

echo "Configuring Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-vicidial"

cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default-vicidial
IsRelative=1
Path=default-vicidial
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$FIREFOX_PROFILE_DIR/default-vicidial/user.js" << USERJS
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage", "about:blank");
user_pref("browser.startup.page", 0);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.resume_session_once", false);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.newtabpage.enabled", false);
USERJS

chown -R ga:ga "$FIREFOX_PROFILE_DIR"

mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/Vicidial.desktop << DESKTOP
[Desktop Entry]
Name=Vicidial (Admin)
Comment=Vicidial Admin Interface
Exec=firefox ${VICIDIAL_ADMIN_URL}
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOP
chown ga:ga /home/ga/Desktop/Vicidial.desktop
chmod +x /home/ga/Desktop/Vicidial.desktop

pkill -f firefox 2>/dev/null || true

echo "Launching Firefox with Vicidial..."
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_vicidial.log 2>&1 &"

for i in $(seq 1 30); do
  WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\\|mozilla\\|vicidial' | head -1 | awk '{print $1}')
  [ -n "$WID" ] && break
  sleep 1
done
if [ -n "$WID" ]; then
  DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== Vicidial setup complete ==="
echo "Vicidial Admin URL: $VICIDIAL_ADMIN_URL"
echo "Expected Vicidial credentials (image default): 6666 / andromeda"
