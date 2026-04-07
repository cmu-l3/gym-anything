#!/bin/bash
set -e

echo "=== Setting up iDempiere ==="

# Wait for desktop to be ready
sleep 5

# ---------------------------------------------------------------
# 1. Prepare iDempiere directory and configuration
# ---------------------------------------------------------------
echo "--- Preparing iDempiere configuration ---"
mkdir -p /home/ga/idempiere
cp /workspace/config/docker-compose.yml /home/ga/idempiere/
chown -R ga:ga /home/ga/idempiere

# ---------------------------------------------------------------
# 2. Pull images and start Docker containers
# ---------------------------------------------------------------
echo "--- Authenticating with Docker Hub to avoid rate limits ---"
# Use Docker Hub credentials if available
if [ -f /workspace/config/.dockerhub_credentials ]; then
    source /workspace/config/.dockerhub_credentials
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin 2>/dev/null || true
fi

echo "--- Pulling Docker images (this may take a few minutes) ---"
cd /home/ga/idempiere
docker compose pull

echo "--- Starting Docker containers ---"
docker compose up -d

# ---------------------------------------------------------------
# 3. Wait for PostgreSQL to be ready
# ---------------------------------------------------------------
echo "--- Waiting for PostgreSQL ---"
POSTGRES_TIMEOUT=120
POSTGRES_ELAPSED=0
while [ $POSTGRES_ELAPSED -lt $POSTGRES_TIMEOUT ]; do
    if docker exec idempiere-postgres pg_isready -U postgres 2>/dev/null | grep -q "accepting connections"; then
        echo "PostgreSQL is ready (${POSTGRES_ELAPSED}s)"
        break
    fi
    sleep 3
    POSTGRES_ELAPSED=$((POSTGRES_ELAPSED + 3))
    echo "  Waiting for PostgreSQL... (${POSTGRES_ELAPSED}s)"
done

# ---------------------------------------------------------------
# 4. Wait for iDempiere to be fully ready
# NOTE: First launch seeds the GardenWorld demo database — takes 10-15 minutes
# ---------------------------------------------------------------
echo "--- Waiting for iDempiere web server (first launch seeds DB, takes up to 20 min) ---"
IDEMPIERE_TIMEOUT=1200
IDEMPIERE_ELAPSED=0
while [ $IDEMPIERE_ELAPSED -lt $IDEMPIERE_TIMEOUT ]; do
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost:8443/webui/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo "iDempiere is ready (HTTP $HTTP_CODE) after ${IDEMPIERE_ELAPSED}s"
        break
    fi
    # Also check HTTP port as fallback
    HTTP_CODE_8080=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/webui/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE_8080" = "200" ] || [ "$HTTP_CODE_8080" = "302" ]; then
        echo "iDempiere is ready on HTTP (HTTP $HTTP_CODE_8080) after ${IDEMPIERE_ELAPSED}s"
        break
    fi
    sleep 10
    IDEMPIERE_ELAPSED=$((IDEMPIERE_ELAPSED + 10))
    if [ $((IDEMPIERE_ELAPSED % 60)) -eq 0 ]; then
        echo "  Still waiting for iDempiere... (${IDEMPIERE_ELAPSED}s) — HTTPS: $HTTP_CODE, HTTP: $HTTP_CODE_8080"
        # Show last few log lines for diagnostics
        docker logs --tail=5 idempiere-app 2>/dev/null || true
    fi
done

# Extra buffer for full initialization
sleep 15

# ---------------------------------------------------------------
# 5. Extract SSL certificate and trust it in Firefox profile
# ---------------------------------------------------------------
echo "--- Extracting iDempiere SSL certificate ---"
# Export the self-signed cert from iDempiere
echo "" | openssl s_client -connect localhost:8443 -servername localhost 2>/dev/null \
    | openssl x509 > /tmp/idempiere.crt 2>/dev/null || true
echo "  SSL cert extracted"

# ---------------------------------------------------------------
# 6. Setup Firefox profile
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"

# Warm-up launch to create default profile
su - ga -c "DISPLAY=:1 firefox --headless &"
sleep 10
pkill -f firefox || true
sleep 3

# Find default profile directory
SNAP_PROFILE_DIR=$(find /home/ga/snap/firefox/common/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
if [ -z "$SNAP_PROFILE_DIR" ]; then
    SNAP_PROFILE_DIR=$(find /home/ga/.mozilla/firefox/ -maxdepth 1 -name '*.default*' -type d 2>/dev/null | head -1)
fi

if [ -n "$SNAP_PROFILE_DIR" ]; then
    echo "  Found Firefox profile at: $SNAP_PROFILE_DIR"

    # Inject user preferences
    cat > "$SNAP_PROFILE_DIR/user.js" << 'FFEOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.startup.homepage", "https://localhost:8443/webui/");
user_pref("browser.newtabpage.enabled", false);
user_pref("browser.startup.page", 1);
user_pref("signon.rememberSignons", false);
user_pref("browser.tabs.warnOnClose", false);
user_pref("browser.tabs.warnOnCloseOtherTabs", false);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("browser.uitour.enabled", false);
user_pref("network.stricttransportsecurity.preloadlist", false);
FFEOF
    chown ga:ga "$SNAP_PROFILE_DIR/user.js"

    # Import the self-signed SSL certificate so Firefox trusts iDempiere
    if [ -f /tmp/idempiere.crt ]; then
        # Try certutil for non-snap Firefox
        if command -v certutil >/dev/null 2>&1; then
            certutil -A -n "iDempiere Self-Signed" -t "CT,," \
                -i /tmp/idempiere.crt -d "$SNAP_PROFILE_DIR" 2>/dev/null || true
        fi
    fi

    echo "  Firefox profile configured"
else
    echo "  WARNING: Could not find Firefox default profile directory"
fi

# Create desktop shortcut
cat > /home/ga/Desktop/iDempiere.desktop << 'DSKEOF'
[Desktop Entry]
Name=iDempiere ERP
Comment=Open Source ERP System
Exec=firefox https://localhost:8443/webui/
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
DSKEOF
chmod +x /home/ga/Desktop/iDempiere.desktop
chown ga:ga /home/ga/Desktop/iDempiere.desktop

# ---------------------------------------------------------------
# 7. Launch Firefox and navigate to iDempiere
# ---------------------------------------------------------------
echo "--- Launching Firefox ---"
su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"

# Wait for Firefox window
echo "--- Waiting for Firefox window ---"
FIREFOX_TIMEOUT=60
FIREFOX_ELAPSED=0
while [ $FIREFOX_ELAPSED -lt $FIREFOX_TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iq "firefox\|mozilla"; then
        echo "Firefox window detected (${FIREFOX_ELAPSED}s)"
        break
    fi
    sleep 3
    FIREFOX_ELAPSED=$((FIREFOX_ELAPSED + 3))
done

sleep 5

# Explicitly focus and maximize Firefox window
# Use wmctrl -xa to activate by WM_CLASS (most reliable focus method)
DISPLAY=:1 wmctrl -xa firefox 2>/dev/null || \
DISPLAY=:1 wmctrl -xa Firefox 2>/dev/null || \
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Use xdotool to focus the Firefox window
FF_WIN=$(DISPLAY=:1 xdotool search --class Firefox 2>/dev/null | head -1)
if [ -n "$FF_WIN" ]; then
    DISPLAY=:1 xdotool windowfocus --sync "$FF_WIN" 2>/dev/null || true
    DISPLAY=:1 xdotool windowactivate --sync "$FF_WIN" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key --window "$FF_WIN" super+Up 2>/dev/null || true
fi

# Maximize using wmctrl after focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 5

# ---------------------------------------------------------------
# 8. Handle SSL certificate warning
# Firefox SSL warning page "Warning: Potential Security Risk Ahead"
# Coordinates confirmed at 1920x1080 via interactive testing:
#   "Advanced..." button:           actual (1319, 752)
#   "Accept the Risk and Continue": actual (1251, 1038)
# ---------------------------------------------------------------
echo "--- Handling SSL certificate warning ---"
sleep 5

# Re-focus Firefox before clicking SSL coords
if [ -n "$FF_WIN" ]; then
    DISPLAY=:1 xdotool windowfocus --sync "$FF_WIN" 2>/dev/null || true
    sleep 0.5
fi

FF_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
echo "  Firefox title: $FF_TITLE"

# Check if SSL warning page is showing
if echo "$FF_TITLE" | grep -qi "warning\|security risk\|potential"; then
    echo "  SSL warning page detected - clicking through..."
    # Click "Advanced..." button
    DISPLAY=:1 xdotool mousemove 1319 752
    sleep 0.5
    DISPLAY=:1 xdotool click 1
    sleep 3
    # Click "Accept the Risk and Continue"
    DISPLAY=:1 xdotool mousemove 1251 1038
    sleep 0.5
    DISPLAY=:1 xdotool click 1
    sleep 8
else
    echo "  No SSL warning detected (title: '$FF_TITLE') — clicking SSL coords anyway as safety measure..."
    # Always try clicking through SSL just in case (no harm if already past it)
    DISPLAY=:1 xdotool mousemove 1319 752
    sleep 0.5
    DISPLAY=:1 xdotool click 1
    sleep 3
    DISPLAY=:1 xdotool mousemove 1251 1038
    sleep 0.5
    DISPLAY=:1 xdotool click 1
    sleep 8
fi

# ---------------------------------------------------------------
# 9. Log in to iDempiere with GardenAdmin credentials
# Login form fields at 1920x1080 (confirmed via interactive testing):
#   User field:     actual (1245, 606)
#   Password field: actual (1245, 639)
#   OK button:      actual (1344, 825)
# ---------------------------------------------------------------
echo "--- Logging into iDempiere ---"
sleep 5

# Click User field
DISPLAY=:1 xdotool mousemove 1245 606
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a
sleep 0.2
DISPLAY=:1 xdotool type --delay 50 "GardenAdmin"
sleep 0.5

# Click Password field
DISPLAY=:1 xdotool mousemove 1245 639
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 0.3
DISPLAY=:1 xdotool type --delay 50 "GardenAdmin"
sleep 0.5

# Click OK button on login form
DISPLAY=:1 xdotool mousemove 1344 825
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 10

# ---------------------------------------------------------------
# 10. Role Selection page
# After login, iDempiere shows a Role Selection page with:
#   Tenant: GardenWorld, Role: GardenWorld Admin, Org: *, Date: today
#   OK button at actual (1230, 858)
# ---------------------------------------------------------------
echo "--- Confirming role selection ---"
sleep 3

# Click OK on role selection page
DISPLAY=:1 xdotool mousemove 1230 858
sleep 0.3
DISPLAY=:1 xdotool click 1
sleep 5

# ---------------------------------------------------------------
# 10. Wait for iDempiere main screen to load
# ---------------------------------------------------------------
echo "--- Waiting for iDempiere dashboard ---"
sleep 10

echo "=== iDempiere setup complete ==="
echo "  URL: https://localhost:8443/webui/"
echo "  Login: GardenAdmin / GardenAdmin (GardenWorld company)"
echo "  Alt login: SuperUser / System (all clients)"
