#!/bin/bash
# Apache OFBiz Setup Script (post_start hook)
# Starts OFBiz via Docker with demo data loaded,
# waits for it to be ready, accepts the self-signed SSL cert,
# and launches Firefox logged in to the Accounting module.
#
# Default credentials: admin / ofbiz
# OFBiz URL: https://localhost:8443

echo "=== Setting up Apache OFBiz via Docker ==="

# Configuration
OFBIZ_URL="https://localhost:8443"
ADMIN_USER="admin"
ADMIN_PASS="ofbiz"
CONTAINER_NAME="ofbiz"

# Ensure Docker is running
echo "Checking Docker service..."
systemctl is-active docker || systemctl start docker
sleep 3

# Stop any existing OFBiz container
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Start OFBiz container with demo data
echo "Starting OFBiz Docker container with demo data..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -e OFBIZ_DATA_LOAD=demo \
    -e OFBIZ_ADMIN_USER="$ADMIN_USER" \
    -e OFBIZ_ADMIN_PASSWORD="$ADMIN_PASS" \
    -p 8443:8443 \
    -p 8080:8080 \
    ghcr.io/apache/ofbiz:release24.09-plugins-snapshot || \
docker run -d \
    --name "$CONTAINER_NAME" \
    -e OFBIZ_DATA_LOAD=demo \
    -e OFBIZ_ADMIN_USER="$ADMIN_USER" \
    -e OFBIZ_ADMIN_PASSWORD="$ADMIN_PASS" \
    -p 8443:8443 \
    -p 8080:8080 \
    ghcr.io/apache/ofbiz:trunk-plugins-snapshot

echo "Container starting..."
docker ps 2>/dev/null || true

# Function to wait for OFBiz to be ready (HTTPS with self-signed cert)
wait_for_ofbiz() {
    local timeout=${1:-600}
    local elapsed=0

    echo "Waiting for OFBiz to be ready (this may take several minutes for first-time data load)..."

    while [ $elapsed -lt $timeout ]; do
        # Use -k to skip SSL certificate verification (self-signed cert)
        HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$OFBIZ_URL/accounting/control/main" 2>/dev/null)
        # 401 means OFBiz is running but requires auth — that's fine, it's ready
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ] || [ "$HTTP_CODE" = "401" ]; then
            echo "OFBiz is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s (HTTP $HTTP_CODE)"
            docker logs --tail 3 "$CONTAINER_NAME" 2>/dev/null || true
        fi
    done

    echo "WARNING: OFBiz readiness check timed out after ${timeout}s"
    return 1
}

# Wait for OFBiz to fully start (demo data loading takes time)
wait_for_ofbiz 600

# Show container status
echo ""
echo "Container status:"
docker ps 2>/dev/null || true

# Set up Firefox profile for user 'ga'
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create Firefox profiles.ini
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

# Create user.js to configure Firefox
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to OFBiz
user_pref("browser.startup.homepage", "https://localhost:8443/accounting/control/main");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Accept enterprise root certificates
user_pref("security.enterprise_roots.enabled", true);

// Disable sidebar, extensions panel, and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.visibility", "hide-sidebar");
user_pref("sidebar.main.tools", "");
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("extensions.getAddons.showPane", false);
user_pref("extensions.htmlaboutaddons.recommendations.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
user_pref("browser.toolbars.bookmarks.visibility", "never");
user_pref("browser.laterrun.enabled", false);

// Disable developer tools from accidentally opening
user_pref("devtools.selfxss.count", 5);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/OFBiz.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=Apache OFBiz
Comment=Enterprise Resource Planning
Exec=firefox https://localhost:8443/accounting/control/main
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;Business;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OFBiz.desktop
chmod +x /home/ga/Desktop/OFBiz.desktop

# ---------------------------------------------------------------
# Launch Firefox and handle the self-signed SSL certificate warning.
# OFBiz uses HTTPS with a self-signed cert, so Firefox will show
# a "Warning: Potential Security Risk Ahead" page on first visit.
# We accept the cert using the browser developer console because
# cert_override.txt and certutil approaches are unreliable.
# ---------------------------------------------------------------
echo "Launching Firefox with OFBiz..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2
rm -f /home/ga/.mozilla/firefox/default-release/.parentlock \
      /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
su - ga -c "DISPLAY=:1 setsid firefox '$OFBIZ_URL/accounting/control/main' > /tmp/firefox_ofbiz.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|ofbiz"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Handle SSL certificate warning using developer console
    echo "Handling SSL certificate warning..."
    sleep 5

    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
    if echo "$TITLE" | grep -qi "warning\|risk\|cert\|error\|secure"; then
        echo "SSL certificate warning detected. Accepting via developer console..."

        # Open developer console (Ctrl+Shift+K)
        DISPLAY=:1 xdotool key ctrl+shift+k
        sleep 3

        # Click the Advanced button via DOM
        DISPLAY=:1 xdotool type --clearmodifiers 'document.getElementById("advancedButton").click()'
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 2

        # Click Accept the Risk and Continue
        DISPLAY=:1 xdotool type --clearmodifiers 'document.getElementById("exceptionDialogButton").click()'
        sleep 0.5
        DISPLAY=:1 xdotool key Return
        sleep 5

        # Close developer console
        DISPLAY=:1 xdotool key F12
        sleep 1

        echo "SSL certificate accepted"
    else
        echo "No SSL warning detected (cert may already be accepted)"
    fi

    # Now log in using URL-based authentication
    echo "Logging into OFBiz via URL auth..."
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --clearmodifiers "${OFBIZ_URL}/accounting/control/main?USERNAME=${ADMIN_USER}&PASSWORD=${ADMIN_PASS}&JavaScriptEnabled=Y"
    sleep 0.3
    DISPLAY=:1 xdotool key Return
    sleep 8

    # Verify login
    LOGIN_OK=false
    for i in {1..15}; do
        TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$TITLE" | grep -qi "accounting\|ofbiz\|manager"; then
            LOGIN_OK=true
            echo "OFBiz login successful (window: $TITLE)"
            break
        fi
        if [ -n "$TITLE" ] && ! echo "$TITLE" | grep -qi "login\|warning\|risk"; then
            LOGIN_OK=true
            echo "OFBiz login successful (no longer on login/warning page)"
            break
        fi
        sleep 2
    done

    if [ "$LOGIN_OK" = false ]; then
        echo "WARNING: Auto-login may not have succeeded."
        echo "Credentials: $ADMIN_USER / $ADMIN_PASS"
    fi
fi

echo ""
echo "=== Apache OFBiz Setup Complete ==="
echo ""
echo "OFBiz is running at: $OFBIZ_URL"
echo "Login: $ADMIN_USER / $ADMIN_PASS"
echo "Modules available:"
echo "  - Accounting: $OFBIZ_URL/accounting/control/main"
echo "  - Order Manager: $OFBIZ_URL/ordermgr/control/main"
echo "  - Catalog: $OFBIZ_URL/catalog/control/main"
echo "  - Party Manager: $OFBIZ_URL/partymgr/control/main"
echo "  - Manufacturing: $OFBIZ_URL/manufacturing/control/main"
echo ""
