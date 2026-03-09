#!/bin/bash
# OpenC3 COSMOS Setup Script (post_start hook)
# Starts COSMOS containers, waits for services, sets admin password, launches Firefox
set -e

echo "=== Setting up OpenC3 COSMOS ==="

# Configuration
OPENC3_URL="http://localhost:2900"
ADMIN_PASSWORD="Cosmos2024!"

# Function to wait for OpenC3 web UI to be ready
wait_for_openc3() {
    local timeout=${1:-600}
    local elapsed=0

    echo "Waiting for OpenC3 COSMOS web UI to be ready..."
    echo "This can take 5-10 minutes on first startup as containers initialize..."

    while [ $elapsed -lt $timeout ]; do
        # Check if Traefik proxy is responding
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OPENC3_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "OpenC3 web UI is responding after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [ $((elapsed % 60)) -eq 0 ]; then
            echo "  Still waiting... ${elapsed}s elapsed (HTTP $HTTP_CODE)"
            # Show container status
            cd /home/ga/cosmos && docker compose ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || true
        fi
    done

    echo "WARNING: OpenC3 readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for the COSMOS API to be fully operational
wait_for_cosmos_api() {
    local timeout=${1:-300}
    local elapsed=0

    echo "Waiting for COSMOS API to be fully operational..."

    while [ $elapsed -lt $timeout ]; do
        # Try to access the API endpoint
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "$OPENC3_URL/openc3-api/api" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"get_target_list","params":[],"id":1,"keyword_params":{"scope":"DEFAULT"}}' \
            2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
            echo "COSMOS API is operational after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  API check... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: COSMOS API readiness timed out after ${timeout}s"
    return 1
}

# Start OpenC3 COSMOS containers
echo "Starting OpenC3 COSMOS..."
cd /home/ga/cosmos

# Start using openc3.sh run (detached mode)
./openc3.sh run 2>&1 | tail -20

echo "Containers starting..."
sleep 10
docker compose ps 2>/dev/null || true

# Wait for web UI to be ready (long timeout - first start pulls images and initializes)
wait_for_openc3 600

# Set the admin password via xdotool in a headless Firefox
# In open-source COSMOS, the auth token IS the password itself
echo "Setting admin password via UI automation..."
AUTH_TOKEN="$ADMIN_PASSWORD"

# Launch Firefox to the login page
su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_pass_setup.log 2>&1 &"
sleep 8

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openc3\|cosmos"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done
sleep 3

# Maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 2

# Check if password is already set
TOKEN_EXISTS=$(curl -s http://localhost:2900/openc3-api/auth/token-exists 2>/dev/null | jq -r '.result // "false"' 2>/dev/null)
echo "Token already exists: $TOKEN_EXISTS"

if [ "$TOKEN_EXISTS" = "false" ]; then
    echo "Setting password via UI..."
    # Click on New Password field (scaled from 1280x720: 750,246 -> 1125,369)
    DISPLAY=:1 xdotool mousemove 1125 369 click 1
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 30 "$ADMIN_PASSWORD"
    sleep 0.5

    # Click on Confirm Password field (scaled: 750,298 -> 1125,447)
    DISPLAY=:1 xdotool mousemove 1125 447 click 1
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 30 "$ADMIN_PASSWORD"
    sleep 0.5

    # Click Set button (scaled: 264,345 -> 396,517)
    DISPLAY=:1 xdotool mousemove 396 517 click 1
    sleep 5
    echo "Password set via UI"
else
    echo "Password already set, skipping UI setup"
fi

# Save the token (which is the password in open-source COSMOS)
echo "$AUTH_TOKEN" > /home/ga/.cosmos_token
chown ga:ga /home/ga/.cosmos_token
chmod 600 /home/ga/.cosmos_token

# Wait for COSMOS API + demo targets to be loaded
wait_for_cosmos_api 300

# Verify demo targets are loaded
echo "Verifying demo targets..."
sleep 5
TARGETS=$(curl -s \
    -X POST "$OPENC3_URL/openc3-api/api" \
    -H "Content-Type: application/json" \
    -H "Authorization: $AUTH_TOKEN" \
    -d '{"jsonrpc":"2.0","method":"get_target_names","params":[],"id":1,"keyword_params":{"scope":"DEFAULT"}}' \
    2>/dev/null)
echo "Available targets: $TARGETS"

# Kill Firefox (will be relaunched after profile setup)
pkill -f firefox 2>/dev/null || true
sleep 2

# Set up Firefox profile for user 'ga'
echo "Setting up Firefox profile..."
IS_SNAP_FIREFOX=false
if snap list firefox 2>/dev/null | grep -q firefox; then
    IS_SNAP_FIREFOX=true
    echo "Detected Snap Firefox installation"
fi

# Firefox user.js configuration
FIREFOX_USERJS='// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to OpenC3 COSMOS
user_pref("browser.startup.homepage", "http://localhost:2900");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("sidebar.main.tools", "");
user_pref("sidebar.nimbus", "");
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
'

PROFILES_INI='[Install4F96D1932A9F858E]
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
'

# Write profile to standard location
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"
echo "$PROFILES_INI" > "$FIREFOX_PROFILE_DIR/profiles.ini"
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"
echo "$FIREFOX_USERJS" > "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# If Snap Firefox, configure Snap profile too
if [ "$IS_SNAP_FIREFOX" = "true" ]; then
    echo "Configuring Snap Firefox profile..."
    su - ga -c "DISPLAY=:1 firefox --headless &" 2>/dev/null || true
    sleep 5
    pkill -f "firefox" 2>/dev/null || true
    sleep 2

    SNAP_PROFILE_DIR="/home/ga/snap/firefox/common/.mozilla/firefox"
    if [ -d "$SNAP_PROFILE_DIR" ]; then
        SNAP_PROFILE=$(find "$SNAP_PROFILE_DIR" -maxdepth 1 -name "*.default-release" -type d | head -1)
        if [ -z "$SNAP_PROFILE" ]; then
            SNAP_PROFILE="$SNAP_PROFILE_DIR/default-release"
            sudo -u ga mkdir -p "$SNAP_PROFILE"
        fi
        echo "$FIREFOX_USERJS" > "$SNAP_PROFILE/user.js"
        chown ga:ga "$SNAP_PROFILE/user.js"
    else
        sudo -u ga mkdir -p "$SNAP_PROFILE_DIR/default-release"
        echo "$PROFILES_INI" > "$SNAP_PROFILE_DIR/profiles.ini"
        echo "$FIREFOX_USERJS" > "$SNAP_PROFILE_DIR/default-release/user.js"
        chown -R ga:ga "/home/ga/snap/firefox"
    fi
fi

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/OpenC3.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=OpenC3 COSMOS
Comment=Satellite Ground Station
Exec=firefox http://localhost:2900
Icon=applications-science
StartupNotify=true
Terminal=false
Type=Application
Categories=Science;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/OpenC3.desktop
chmod +x /home/ga/Desktop/OpenC3.desktop

# Create utility scripts for COSMOS operations
cat > /usr/local/bin/cosmos-api << 'APISCRIPT'
#!/bin/bash
# Query OpenC3 COSMOS JSON-RPC API
OPENC3_URL="http://localhost:2900"
TOKEN=$(cat /home/ga/.cosmos_token 2>/dev/null || echo "")

METHOD="$1"
shift
PARAMS="$*"

curl -s -X POST "$OPENC3_URL/openc3-api/api" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"$METHOD\",\"params\":[$PARAMS],\"id\":1,\"keyword_params\":{\"scope\":\"DEFAULT\"}}"
APISCRIPT
chmod +x /usr/local/bin/cosmos-api

# Create a telemetry query utility
cat > /usr/local/bin/cosmos-tlm << 'TLMSCRIPT'
#!/bin/bash
# Read a single telemetry point: cosmos-tlm "INST HEALTH_STATUS TEMP1"
OPENC3_URL="http://localhost:2900"
TOKEN=$(cat /home/ga/.cosmos_token 2>/dev/null || echo "")

TLM_POINT="$1"

curl -s -X POST "$OPENC3_URL/openc3-api/api" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"tlm\",\"params\":[\"$TLM_POINT\"],\"id\":1,\"keyword_params\":{\"type\":\"FORMATTED\",\"scope\":\"DEFAULT\"}}" | jq -r '.result'
TLMSCRIPT
chmod +x /usr/local/bin/cosmos-tlm

# Create a command sender utility
cat > /usr/local/bin/cosmos-cmd << 'CMDSCRIPT'
#!/bin/bash
# Send a command: cosmos-cmd "INST COLLECT with DURATION 1.0, TYPE 'NORMAL'"
OPENC3_URL="http://localhost:2900"
TOKEN=$(cat /home/ga/.cosmos_token 2>/dev/null || echo "")

CMD_STRING="$1"

curl -s -X POST "$OPENC3_URL/openc3-api/api" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"cmd\",\"params\":[\"$CMD_STRING\"],\"id\":1,\"keyword_params\":{\"scope\":\"DEFAULT\"}}" | jq '.'
CMDSCRIPT
chmod +x /usr/local/bin/cosmos-cmd

# Launch Firefox with COSMOS
echo "Launching Firefox with OpenC3 COSMOS..."
su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_cosmos.log 2>&1 &"

# Wait for Firefox window
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|openc3\|cosmos"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    sleep 2
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

echo ""
echo "=== OpenC3 COSMOS Setup Complete ==="
echo ""
echo "OpenC3 COSMOS is running at: $OPENC3_URL"
echo ""
echo "Admin Password: $ADMIN_PASSWORD"
echo ""
echo "Available Tools:"
echo "  - Command and Telemetry Server"
echo "  - Command Sender"
echo "  - Telemetry Viewer"
echo "  - Telemetry Grapher"
echo "  - Packet Viewer"
echo "  - Limits Monitor"
echo "  - Script Runner"
echo "  - Data Extractor"
echo ""
echo "Demo Targets: INST, INST2, EXAMPLE, TEMPLATED"
echo ""
echo "CLI Utilities:"
echo "  cosmos-api <method> [params]"
echo "  cosmos-tlm 'INST HEALTH_STATUS TEMP1'"
echo "  cosmos-cmd 'INST COLLECT with DURATION 1.0, TYPE NORMAL'"
echo ""
echo "Docker commands:"
echo "  cd /home/ga/cosmos && docker compose ps"
echo "  cd /home/ga/cosmos && docker compose logs -f"
echo ""
