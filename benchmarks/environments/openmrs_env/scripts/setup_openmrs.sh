#!/bin/bash
# OpenMRS O3 Setup Script (post_start hook)
# Starts OpenMRS O3 via Docker Compose, waits for readiness,
# seeds demo data via REST API, and launches Firefox.
#
# OpenMRS O3 credentials: admin / Admin123
# URL: http://localhost/openmrs/spa

set -e

echo "=== Setting up OpenMRS O3 ==="

OMRS_URL="http://localhost/openmrs"
SPA_URL="http://localhost/openmrs/spa"
ADMIN_USER="admin"
ADMIN_PASS="Admin123"
COMPOSE_FILE="/home/ga/openmrs/docker-compose.yml"

# ── Helper: poll until HTTP 200 ───────────────────────────────────────────────
wait_for_http() {
    local url="$1"
    local timeout="${2:-300}"
    local elapsed=0
    echo "Polling $url (timeout ${timeout}s)..."
    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "  Ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done
    echo "WARNING: Timeout waiting for $url after ${timeout}s"
    return 1
}

# ── 1. Set up docker-compose directory ───────────────────────────────────────
echo "Preparing OpenMRS directory..."
mkdir -p /home/ga/openmrs
cp /workspace/config/docker-compose.yml "$COMPOSE_FILE"
chown -R ga:ga /home/ga/openmrs

# ── 2. Pull images and start containers ──────────────────────────────────────
echo "Pulling OpenMRS O3 Docker images..."
cd /home/ga/openmrs
docker compose -f "$COMPOSE_FILE" pull

echo "Starting OpenMRS O3 containers..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Containers started:"
docker compose -f "$COMPOSE_FILE" ps

# ── 3. Wait for backend to be fully initialised ───────────────────────────────
# O3 backend first-boot initializes DB, loads modules, and creates demo data.
# This can take 5-10 minutes on first run.
echo "Waiting for OpenMRS backend to initialize (first boot is slow)..."
wait_for_http "${OMRS_URL}/health/started" 600

echo "Waiting for OpenMRS frontend/gateway..."
wait_for_http "${SPA_URL}" 120

echo ""
echo "Container status after startup:"
docker compose -f "$COMPOSE_FILE" ps

# ── 4. Seed structured demo data via REST API ─────────────────────────────────
echo "Seeding structured demo patients and clinical data..."
bash /workspace/scripts/seed_data.sh || echo "WARNING: Data seeding had errors (non-fatal)"

# ── 5. Firefox profile setup ─────────────────────────────────────────────────
echo "Configuring Firefox profile..."
FIREFOX_DIR="/home/ga/.mozilla/firefox"
PROFILE_DIR="$FIREFOX_DIR/openmrs.default"
sudo -u ga mkdir -p "$PROFILE_DIR"

cat > "$FIREFOX_DIR/profiles.ini" << 'FFINI'
[Install4F96D1932A9F858E]
Default=openmrs.default
Locked=1

[Profile0]
Name=openmrs
IsRelative=1
Path=openmrs.default
Default=1

[General]
StartWithLastProfile=1
Version=2
FFINI

cat > "$PROFILE_DIR/user.js" << USERJS
// Disable first-run dialogs
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
// Homepage = OpenMRS O3 SPA login
user_pref("browser.startup.homepage", "${SPA_URL}/login");
user_pref("browser.startup.page", 1);
// Disable updates
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);
// Disable password saving
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
// Disable sidebar/promo
user_pref("sidebar.revamp", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
// Disable session restore prompts
user_pref("browser.sessionstore.resume_from_crash", false);
USERJS

chown -R ga:ga "$FIREFOX_DIR"

# ── 6. Launch Firefox ─────────────────────────────────────────────────────────
echo "Launching Firefox with OpenMRS O3..."
su - ga -c "DISPLAY=:1 firefox '${SPA_URL}/login' > /tmp/firefox_openmrs.log 2>&1 &"

# Wait for Firefox window
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openmrs"; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 2

# Maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# ── 7. Create db-query utility ────────────────────────────────────────────────
cat > /usr/local/bin/openmrs-db-query << 'DBEOF'
#!/bin/bash
docker exec $(docker ps --filter name=openmrs_env-db -q || docker ps --filter name=db -q | head -1) \
    mariadb -u openmrs -popenmrs openmrs -N -e "$1" 2>/dev/null
DBEOF
chmod +x /usr/local/bin/openmrs-db-query

echo ""
echo "=== OpenMRS O3 Setup Complete ==="
echo ""
echo "URL:      ${SPA_URL}"
echo "Login:    ${ADMIN_USER} / ${ADMIN_PASS}"
echo "REST API: ${OMRS_URL}/ws/rest/v1/"
echo ""
echo "DB access: docker exec <db-container> mariadb -u openmrs -popenmrs openmrs -e \"SQL\""
