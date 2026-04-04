#!/bin/bash
set -euo pipefail

echo "=== Setting up SEB Server ==="

# ============================================================
# Wait for desktop to be ready
# ============================================================
echo "Waiting for X display..."
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 xset q >/dev/null 2>&1; then
        echo "X display is ready"
        break
    fi
    sleep 2
done

# ============================================================
# Start Docker Compose services
# ============================================================
echo "=== Starting SEB Server Docker services ==="
cd /opt/seb-server

# Start MariaDB first
docker compose up -d mariadb
echo "Waiting for MariaDB..."

# Poll for MariaDB readiness
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker exec seb-server-mariadb mysqladmin ping -h localhost 2>/dev/null | grep -q "alive"; then
        echo "MariaDB is ready after ${ELAPSED}s"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: MariaDB did not start within ${TIMEOUT}s"
    docker logs seb-server-mariadb 2>&1 | tail -20
fi

# Start SEB Server
docker compose up -d seb-server
echo "Waiting for SEB Server to start (Java app, may take 2-3 minutes)..."

# Poll for SEB Server readiness
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/gui" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "SEB Server is ready after ${ELAPSED}s (HTTP $HTTP_CODE)"
        break
    fi
    # Also check root endpoint — 401 means server is up (needs auth)
    ROOT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" 2>/dev/null || echo "000")
    if [ "$ROOT_CODE" = "401" ]; then
        echo "SEB Server is ready after ${ELAPSED}s (root HTTP $ROOT_CODE)"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "  Still waiting... (${ELAPSED}s elapsed, last HTTP: $HTTP_CODE)"
    fi
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "ERROR: SEB Server did not start within ${TIMEOUT}s"
    docker logs seb-server 2>&1 | tail -30
fi

# Extra wait for the Java app to fully initialize all endpoints
sleep 10

echo "=== Verifying SEB Server ==="
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/gui" 2>/dev/null || echo "000")
echo "SEB Server GUI HTTP status: $HTTP_CODE"

# ============================================================
# Seed realistic exam data via REST API
# ============================================================
echo "=== Seeding exam data ==="
if [ -f /workspace/data/seed_exam_data.py ]; then
    python3 /workspace/data/seed_exam_data.py 2>&1 || echo "WARNING: Data seeding had issues"
fi

# ============================================================
# Configure Firefox profile (two-layer dialog suppression)
# ============================================================
echo "=== Configuring Firefox ==="

# Determine Firefox profile location (snap vs regular)
if snap list firefox 2>/dev/null | grep -q firefox; then
    FIREFOX_PROFILE_BASE="/home/ga/snap/firefox/common/.mozilla/firefox"
else
    FIREFOX_PROFILE_BASE="/home/ga/.mozilla/firefox"
fi

PROFILE_DIR="${FIREFOX_PROFILE_BASE}/seb.profile"
mkdir -p "$PROFILE_DIR"

# Write profiles.ini
cat > "${FIREFOX_PROFILE_BASE}/profiles.ini" << 'EOF'
[Profile0]
Name=seb
IsRelative=1
Path=seb.profile
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF

# Write user.js to suppress all first-run dialogs
cat > "${PROFILE_DIR}/user.js" << 'EOF'
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("browser.startup.homepage", "http://localhost:8080");
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("app.update.enabled", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.aboutConfig.showWarning", false);
EOF

chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true
chown -R ga:ga /home/ga/snap 2>/dev/null || true

# ============================================================
# Warm-up launch: open Firefox once to clear first-run state
# ============================================================
echo "=== Firefox warm-up launch ==="

# Remove stale locks
find "${FIREFOX_PROFILE_BASE}" -name "lock" -o -name ".parentlock" 2>/dev/null | xargs rm -f 2>/dev/null || true

# Launch Firefox briefly to initialize profile
su - ga -c "DISPLAY=:1 setsid firefox --new-instance -profile '${PROFILE_DIR}' 'about:blank' > /tmp/firefox_warmup.log 2>&1 &"
sleep 15

# Dismiss any first-run dialogs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Kill Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Remove stale session data
find "${PROFILE_DIR}" -name "sessionstore*" -delete 2>/dev/null || true
rm -rf "${PROFILE_DIR}/sessionstore-backups" 2>/dev/null || true
find "${FIREFOX_PROFILE_BASE}" -name "lock" -o -name ".parentlock" 2>/dev/null | xargs rm -f 2>/dev/null || true

echo "=== SEB Server setup complete ==="
echo "SEB Server accessible at: http://localhost:8080"
echo "Default login: super-admin / admin"
