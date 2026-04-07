#!/bin/bash
# Do NOT use set -e: some steps may fail transiently

echo "=== Setting up Axelor Open Suite ==="

# ── Configuration ─────────────────────────────────────────────────────────
AXELOR_URL="http://localhost"
AXELOR_DB_NAME="axelor"
ADMIN_USER="admin"
ADMIN_PASS="admin"

# ── 1. Ensure Docker is running and set up Axelor ────────────────────────
echo "--- Setting up Axelor container ---"
systemctl is-active docker || systemctl start docker
sleep 3

# Copy docker-compose.yml
mkdir -p /home/ga/axelor
cp /workspace/config/docker-compose.yml /home/ga/axelor/
chown -R ga:ga /home/ga/axelor
cd /home/ga/axelor

# Tear down any prior run
docker compose down -v 2>/dev/null || true
sleep 2

# Pull Docker image
echo "--- Pulling Axelor Docker image ---"
docker pull axelor/aio-erp:latest 2>&1 || {
    echo "First pull attempt failed, retrying..."
    sleep 10
    docker pull axelor/aio-erp:latest 2>&1 || echo "WARNING: Docker pull failed"
}
echo "Docker images:"
docker images | head -5

# Start the all-in-one Axelor container
echo "--- Starting Axelor container ---"
docker compose up -d 2>&1
sleep 10

# Wait for Axelor to be ready
wait_for_axelor() {
    local timeout=1800
    local elapsed=0
    echo "Waiting for Axelor to start (first run can take 15-30 minutes)..."
    while [ $elapsed -lt $timeout ]; do
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" 2>/dev/null || echo "000")
        if [ "$http_code" = "000" ]; then
            http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/" 2>/dev/null || echo "000")
        fi
        if [ "$http_code" = "200" ] || [ "$http_code" = "302" ] || [ "$http_code" = "303" ]; then
            echo "Axelor is ready (HTTP ${http_code}, ${elapsed}s)"
            if curl -sf "http://localhost/" > /dev/null 2>&1; then
                AXELOR_URL="http://localhost"
            elif curl -sf "http://localhost:8080/" > /dev/null 2>&1; then
                AXELOR_URL="http://localhost:8080"
            fi
            return 0
        fi
        if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo "  Still waiting... (${elapsed}s, HTTP ${http_code})"
            if ! docker ps --format '{{.Names}}' | grep -q axelor-app; then
                echo "  WARNING: axelor-app container stopped, restarting..."
                docker compose up -d 2>&1
            fi
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo "ERROR: Axelor did not become ready within ${timeout}s"
    docker logs axelor-app --tail 50 2>/dev/null || true
    return 1
}
wait_for_axelor

sleep 15
echo "--- Axelor is running at ${AXELOR_URL} ---"
echo "${AXELOR_URL}" > /tmp/axelor_url
chmod 666 /tmp/axelor_url

# ── 1b. Install core modules via API (Base, CRM, Sale, Purchase) ─────────
echo "--- Installing Axelor modules ---"
python3 /workspace/utils/install_modules.py 2>&1 || echo "WARNING: Module installation may have failed"
echo "  Module installation complete."

# ── 2. Set up Firefox (snap) ─────────────────────────────────────────────
echo "--- Configuring Firefox ---"
export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Warm-up: launch Firefox headless to create snap profile
sudo -u ga DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority firefox --headless &
sleep 8
pkill -f "firefox.*headless" 2>/dev/null || true
sleep 2

# Find the auto-generated snap profile directory
SNAP_PROFILE=$(find /home/ga/snap/firefox/common/.mozilla/firefox -maxdepth 1 -name "*.default*" -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE" ]; then
    SNAP_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox/axelor.default"
    mkdir -p "$SNAP_PROFILE"
fi
echo "Firefox profile: $SNAP_PROFILE"

# Inject user.js preferences
cat > "$SNAP_PROFILE/user.js" << EOF
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.disableResetPrompt", true);
user_pref("browser.feeds.showFirstRunUI", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);
user_pref("browser.startup.firstrunSkipsHomepage", true);
user_pref("browser.urlbar.showSearchSuggestionsFirst", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.vpn_promo.enabled", false);
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.startup.homepage", "${AXELOR_URL}/");
user_pref("browser.startup.page", 1);
user_pref("browser.newtabpage.enabled", false);
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);
user_pref("signon.generation.enabled", false);
user_pref("extensions.formautofill.creditCards.enabled", false);
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.memory.enable", true);
EOF
chown -R ga:ga /home/ga/snap/firefox 2>/dev/null || true

# ── 3. Create desktop shortcut ───────────────────────────────────────────
cat > /home/ga/Desktop/Axelor.desktop << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Axelor ERP
Comment=Open Axelor Open Suite
Exec=firefox ${AXELOR_URL}/
Icon=firefox
Terminal=false
Categories=Office;Finance;
StartupNotify=true
EOF
chmod +x /home/ga/Desktop/Axelor.desktop
chown ga:ga /home/ga/Desktop/Axelor.desktop

# ── 4. Create database query utility ─────────────────────────────────────
cat > /usr/local/bin/axelor-db-query << 'DBSCRIPT'
#!/bin/bash
docker exec -e PGPASSWORD=axelor axelor-app psql -U axelor -d axelor -h localhost -t -A -F'|' -c "$1" 2>/dev/null
DBSCRIPT
chmod +x /usr/local/bin/axelor-db-query

# ── 5. Launch Firefox to Axelor login page ───────────────────────────────
echo "--- Launching Firefox ---"
# Use sudo -u ga with explicit env vars (snap Firefox doesn't work with su)
sudo -u ga DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority \
    setsid firefox "${AXELOR_URL}/" > /tmp/firefox.log 2>&1 &

WAIT_FF=0
while [ $WAIT_FF -lt 30 ]; do
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|axelor"; then
        echo "Firefox window detected"
        break
    fi
    sleep 2
    WAIT_FF=$((WAIT_FF + 2))
done

sleep 3
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# ── 6. Flush data for snapshot consistency ────────────────────────────────
echo "--- Flushing data for snapshot ---"
docker exec -e PGPASSWORD=axelor axelor-app psql -U axelor -d axelor -h localhost -c "CHECKPOINT;" 2>/dev/null || true
sync

echo "=== Axelor setup complete ==="
echo "Access Axelor at: ${AXELOR_URL}/"
echo "Login: ${ADMIN_USER} / ${ADMIN_PASS}"
