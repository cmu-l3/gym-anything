#!/bin/bash
set -e

echo "=== Setting up CMDBuild ==="

CMDBUILD_DIR="/home/ga/cmdbuild"
CMDBUILD_URL="http://localhost:8090/cmdbuild/ui/"

mkdir -p "$CMDBUILD_DIR"
cp /workspace/config/docker-compose.yml "$CMDBUILD_DIR/docker-compose.yml"
chown -R ga:ga "$CMDBUILD_DIR"

if command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  DC="docker compose"
fi

wait_for_http() {
  local url="$1"
  local timeout="${2:-600}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [ "$code" = "200" ] || [ "$code" = "302" ]; then
      echo "CMDBuild reachable at $url after ${elapsed}s (HTTP $code)"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "  Waiting for CMDBuild... ${elapsed}s (HTTP $code)"
  done
  echo "ERROR: Timeout waiting for CMDBuild at $url"
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
    echo "  Waiting for $container health... ${elapsed}s (status=$status)"
  done
  echo "ERROR: Timeout waiting for $container health"
  docker logs --tail 60 "$container" || true
  return 1
}

cd "$CMDBUILD_DIR"

$DC up -d
$DC ps

wait_for_health cmdbuild_db 240
wait_for_health cmdbuild_app 600
wait_for_http "$CMDBUILD_URL" 600

# Check if system needs patches applied (first boot with demo data)
echo "Checking boot status..."
BOOT_STATUS=$(curl -s 'http://localhost:8090/cmdbuild/services/rest/v3/boot/status' -H 'Authorization: Basic YWRtaW46YWRtaW4=' 2>/dev/null || echo '{}')
echo "Boot status: $BOOT_STATUS"
if echo "$BOOT_STATUS" | grep -q "WAITING_FOR_PATCH_MANAGER"; then
  echo "Applying pending patches..."
  curl -s -X POST 'http://localhost:8090/cmdbuild/services/rest/v3/boot/patches/apply' \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Basic YWRtaW46YWRtaW4=' 2>/dev/null || true
  # Wait for patches to complete
  PATCH_TIMEOUT=300
  PATCH_ELAPSED=0
  while [ "$PATCH_ELAPSED" -lt "$PATCH_TIMEOUT" ]; do
    BSTATUS=$(curl -s 'http://localhost:8090/cmdbuild/services/rest/v3/boot/status' -H 'Authorization: Basic YWRtaW46YWRtaW4=' 2>/dev/null || echo '{}')
    if echo "$BSTATUS" | grep -q '"READY"'; then
      echo "CMDBuild is READY after patching (${PATCH_ELAPSED}s)"
      break
    fi
    sleep 5
    PATCH_ELAPSED=$((PATCH_ELAPSED + 5))
    echo "  Waiting for patch completion... ${PATCH_ELAPSED}s"
  done
fi

# Wait for API to be fully available (not just HTTP 200)
echo "Waiting for REST API..."
API_TIMEOUT=120
API_ELAPSED=0
while [ "$API_ELAPSED" -lt "$API_TIMEOUT" ]; do
  API_RESP=$(curl -s 'http://localhost:8090/cmdbuild/services/rest/v3/classes?limit=1' \
    -H 'Authorization: Basic YWRtaW46YWRtaW4=' 2>/dev/null || echo '{}')
  if echo "$API_RESP" | grep -q '"success":true'; then
    echo "REST API available after ${API_ELAPSED}s"
    break
  fi
  sleep 3
  API_ELAPSED=$((API_ELAPSED + 3))
done

# Verify API is ready for writes, then seed data (all in one Python script
# to avoid shell-escaping issues with JSON filter URLs)
echo "Verifying API write-readiness and seeding data..."
rm -f /tmp/seed_data_info.json 2>/dev/null || true
python3 -c "
import sys, time, json, urllib.request, urllib.error, base64
sys.path.insert(0, '/workspace/scripts')
from cmdbuild_api import api, get_token, create_card, delete_card, get_cards

# Wait for write-readiness
for attempt in range(20):
    try:
        card_id = create_card('Server', {'Code': '_WRITE_TEST', 'Description': 'write readiness probe'}, 'basic')
        if card_id:
            print(f'API writes ready after {attempt * 3}s')
            delete_card('Server', card_id, 'basic')
            print('Write-test record cleaned up')
            break
    except Exception:
        pass
    time.sleep(3)
else:
    print('WARNING: Write-readiness check timed out, proceeding anyway', file=sys.stderr)
"

# Seed realistic IT infrastructure data via the API
echo "Seeding IT infrastructure data..."
python3 /workspace/scripts/seed_data.py

echo "Configuring Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-cmdbuild"

cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Profile0]
Name=default-cmdbuild
IsRelative=1
Path=default-cmdbuild
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE

cat > "$FIREFOX_PROFILE_DIR/default-cmdbuild/user.js" << 'USERJS'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.homepage", "http://localhost:8090/cmdbuild/ui/");
user_pref("browser.startup.page", 1);
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.newtabpage.enabled", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.resume_session_once", false);
user_pref("browser.startup.couldRestoreSession.count", -1);
user_pref("browser.sessionstore.max_resumed_crashes", 0);
USERJS

chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create DB query shortcut
cat > /usr/local/bin/cmdbuild-db-query << 'EOQ'
#!/bin/bash
docker exec cmdbuild_db psql -U postgres -d cmdbuild_db4 -At -c "$1"
EOQ
chmod +x /usr/local/bin/cmdbuild-db-query

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/CMDBuild.desktop << 'DESKTOP'
[Desktop Entry]
Name=CMDBuild
Comment=CMDBuild IT Asset Management
Exec=firefox http://localhost:8090/cmdbuild/ui/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOP
chown ga:ga /home/ga/Desktop/CMDBuild.desktop
chmod +x /home/ga/Desktop/CMDBuild.desktop

# Kill any existing Firefox and launch fresh
pkill -f firefox || true
sleep 1

echo "Launching Firefox with CMDBuild..."
su - ga -c "DISPLAY=:1 firefox '$CMDBUILD_URL' > /tmp/firefox_cmdbuild.log 2>&1 &"

sleep 6
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'firefox\|mozilla\|cmdbuild' | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
  DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
  DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

echo "=== CMDBuild setup complete ==="
echo "CMDBuild URL: $CMDBUILD_URL"
echo "CMDBuild credentials: admin / admin"
