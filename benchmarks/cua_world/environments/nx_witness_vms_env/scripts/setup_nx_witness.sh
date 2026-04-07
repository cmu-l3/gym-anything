#!/bin/bash
set -e

echo "=== Setting up Nx Witness VMS ==="

NX_DEFAULT_PASS="admin"
NX_ADMIN_PASS="Admin1234!"
NX_SYSTEM_NAME="GymAnythingVMS"
NX_BASE="https://localhost:7001"

# Wait for desktop to be ready
sleep 5

# ============================================================
# Step 1: Start the Nx Witness Media Server
# ============================================================
echo "=== Step 1: Starting Nx Witness Media Server ==="
systemctl enable networkoptix-mediaserver 2>/dev/null || true
systemctl start networkoptix-mediaserver 2>/dev/null || true

wait_for_nx_server() {
    local timeout=120
    local elapsed=0
    echo "Waiting for Nx Witness server to start..."
    while [ $elapsed -lt $timeout ]; do
        if curl -sk "${NX_BASE}/rest/v1/system/info" --max-time 5 | grep -q '"version"'; then
            echo "Nx Witness server is up after ${elapsed}s"
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    echo "ERROR: Nx Witness server did not start within ${timeout}s"
    systemctl status networkoptix-mediaserver || true
    return 1
}
wait_for_nx_server

# ============================================================
# Step 2: Initialize system via setup API (correct format)
# ============================================================
# CRITICAL: The correct flow is:
#   1. Login with admin/admin to get Bearer token
#   2. POST /rest/v1/system/setup with that token and {"local":{"password":"..."}}
#   3. This atomically sets system name AND changes password
#   4. Do NOT change password separately before calling setup — causes "Cannot initialize System"
# ============================================================
echo "=== Step 2: Initializing system via setup API ==="

# Check if already initialized (localSystemId is not null UUID)
SYSTEM_INFO=$(curl -sk "${NX_BASE}/rest/v1/system/info" --max-time 10 2>/dev/null || echo "{}")
LOCAL_SYSTEM_ID=$(echo "$SYSTEM_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('localSystemId',''))" 2>/dev/null || echo "")
NULL_UUID="{00000000-0000-0000-0000-000000000000}"

if [ "$LOCAL_SYSTEM_ID" = "$NULL_UUID" ] || [ -z "$LOCAL_SYSTEM_ID" ]; then
    echo "System not yet initialized, running setup..."

    # Get Bearer token with default admin/admin
    NX_TOKEN=$(curl -sk -X POST "${NX_BASE}/rest/v1/login/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"admin\", \"password\": \"${NX_DEFAULT_PASS}\"}" \
        --max-time 15 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")

    if [ -z "$NX_TOKEN" ]; then
        echo "WARNING: Could not get token with default password — may already be initialized"
        # Try with our password
        NX_TOKEN=$(curl -sk -X POST "${NX_BASE}/rest/v1/login/sessions" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"admin\", \"password\": \"${NX_ADMIN_PASS}\"}" \
            --max-time 15 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")
    fi

    if [ -n "$NX_TOKEN" ]; then
        echo "Got Bearer token, calling system/setup..."
        SETUP_RESULT=$(curl -sk -X POST "${NX_BASE}/rest/v1/system/setup" \
            -H "Authorization: Bearer ${NX_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${NX_SYSTEM_NAME}\", \"settingsPreset\": \"security\", \"settings\": {}, \"local\": {\"password\": \"${NX_ADMIN_PASS}\"}}" \
            --max-time 30 2>/dev/null || echo "")
        echo "Setup result: $(echo "$SETUP_RESULT" | head -c 200)"
        sleep 5

        # Verify initialization
        NEW_INFO=$(curl -sk "${NX_BASE}/rest/v1/system/info" --max-time 10 2>/dev/null || echo "{}")
        NEW_ID=$(echo "$NEW_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('localSystemId',''))" 2>/dev/null || echo "")
        echo "New localSystemId: $NEW_ID"
        if [ "$NEW_ID" != "$NULL_UUID" ] && [ -n "$NEW_ID" ]; then
            echo "System successfully initialized!"
        else
            echo "WARNING: System may not have initialized correctly"
        fi
    else
        echo "ERROR: Cannot authenticate to Nx Witness"
    fi
else
    echo "System already initialized (localSystemId: $LOCAL_SYSTEM_ID)"
fi

# ============================================================
# Step 3: Get fresh auth token with new password
# ============================================================
echo "=== Step 3: Authenticating with new password ==="

NX_TOKEN=$(curl -sk -X POST "${NX_BASE}/rest/v1/login/sessions" \
    -H "Content-Type: application/json" \
    -d "{\"username\": \"admin\", \"password\": \"${NX_ADMIN_PASS}\"}" \
    --max-time 15 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")

if [ -z "$NX_TOKEN" ]; then
    echo "ERROR: Cannot authenticate with admin password after setup"
    # Last resort: try default
    NX_TOKEN=$(curl -sk -X POST "${NX_BASE}/rest/v1/login/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"admin\", \"password\": \"${NX_DEFAULT_PASS}\"}" \
        --max-time 15 | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token',''))" 2>/dev/null || echo "")
fi

echo "Auth token: ${NX_TOKEN:0:20}..."
echo "$NX_TOKEN" > /home/ga/nx_token.txt
chown ga:ga /home/ga/nx_token.txt

# ============================================================
# Step 4: Create virtual test cameras using testcamera
# ============================================================
echo "=== Step 4: Starting virtual test cameras ==="

# Create test video files for testcamera
mkdir -p /home/ga/test_videos

ffmpeg -f lavfi -i "testsrc=duration=30:size=1280x720:rate=25" \
    -f lavfi -i "sine=frequency=1000:duration=30" \
    -c:v libx264 -c:a aac -y \
    /home/ga/test_videos/camera_stream.mp4 2>/dev/null || \
ffmpeg -f lavfi -i "testsrc=duration=30:size=640x480:rate=15" \
    -c:v libx264 -y \
    /home/ga/test_videos/camera_stream.mp4 2>/dev/null || true

chown -R ga:ga /home/ga/test_videos

# Find testcamera binary
TESTCAMERA=$(find /opt -name testcamera -type f 2>/dev/null | head -1)

if [ -n "$TESTCAMERA" ]; then
    echo "Found testcamera at: $TESTCAMERA"

    # Get server's local IP (the one the media server binds to)
    SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "10.0.2.15")
    echo "Using server interface: ${SERVER_IP}"

    # Start testcamera — it uses RTSP auto-discovery on the LAN
    # --local-interface ensures it discovers to the correct NIC
    if [ -f /home/ga/test_videos/camera_stream.mp4 ]; then
        nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" \
            "files=/home/ga/test_videos/camera_stream.mp4;count=3" \
            > /tmp/testcamera.log 2>&1 &
        echo "Testcamera started (PID: $!), waiting for camera discovery..."
    else
        # No video file — use testcamera with live test signal
        nohup "$TESTCAMERA" --local-interface="${SERVER_IP}" \
            "channels=3" \
            > /tmp/testcamera.log 2>&1 &
        echo "Testcamera started with live test channels (PID: $!)"
    fi

    # Wait for cameras to be discovered
    sleep 20
else
    echo "WARNING: testcamera not found, skipping virtual cameras"
fi

# Wait for cameras to register with the server
wait_for_cameras() {
    local timeout=90
    local elapsed=0
    echo "Waiting for cameras to be discovered..."
    while [ $elapsed -lt $timeout ]; do
        local count
        count=$(curl -sk "${NX_BASE}/rest/v1/devices" \
            -H "Authorization: Bearer ${NX_TOKEN}" --max-time 10 | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)" 2>/dev/null || echo "0")
        echo "  Cameras discovered: $count (${elapsed}s elapsed)"
        if [ "$count" -gt 0 ]; then
            echo "Cameras found!"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    echo "No cameras discovered after ${timeout}s — continuing anyway"
    return 0
}
wait_for_cameras

# ============================================================
# Step 5: Rename cameras to meaningful names
# ============================================================
echo "=== Step 5: Naming cameras ==="

CAMERA_NAMES=("Parking Lot Camera" "Entrance Camera" "Server Room Camera" "Lobby Camera" "Loading Dock Camera")

DEVICES_JSON=$(curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${NX_TOKEN}" --max-time 15 2>/dev/null || echo "[]")

echo "$DEVICES_JSON" | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    for d in devices:
        print(d.get('id', ''))
except:
    pass
" 2>/dev/null | {
    IDX=0
    while read device_id; do
        if [ -n "$device_id" ] && [ $IDX -lt 5 ]; then
            CAMERA_NAME="${CAMERA_NAMES[$IDX]}"
            echo "  Naming camera $device_id: $CAMERA_NAME"
            curl -sk -X PATCH "${NX_BASE}/rest/v1/devices/${device_id}" \
                -H "Authorization: Bearer ${NX_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{\"name\": \"${CAMERA_NAME}\"}" \
                --max-time 15 2>/dev/null || true
            IDX=$((IDX + 1))
        fi
    done
}

# ============================================================
# Step 6: Create operator users via REST API
# ============================================================
echo "=== Step 6: Creating operator users ==="

create_nx_user() {
    local username="$1"
    local fullname="$2"
    local email="$3"
    local password="$4"

    local result
    result=$(curl -sk -X POST "${NX_BASE}/rest/v1/users" \
        -H "Authorization: Bearer ${NX_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${username}\", \"fullName\": \"${fullname}\", \"email\": \"${email}\", \"password\": \"${password}\", \"permissions\": \"NoGlobalPermissions\"}" \
        --max-time 15 2>/dev/null || echo "{}")
    echo "  User $username: $(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d.get('errorString', 'unknown')))" 2>/dev/null || echo "done")"
    sleep 1
}

create_nx_user "security.operator" "Security Operator" "security@gymvms.local" "Operator2024!"
create_nx_user "camera.admin" "Camera Administrator" "camadmin@gymvms.local" "CamAdmin2024!"
create_nx_user "site.manager" "Site Manager" "manager@gymvms.local" "Manager2024!"
create_nx_user "john.smith" "John Smith" "john.smith@gymvms.local" "JohnSmith2024!"
create_nx_user "sarah.jones" "Sarah Jones" "sarah.jones@gymvms.local" "SarahJones2024!"

echo "Users created"

# ============================================================
# Step 7: Save state files for tasks
# ============================================================
echo "=== Step 7: Saving state files ==="

curl -sk "${NX_BASE}/rest/v1/devices" \
    -H "Authorization: Bearer ${NX_TOKEN}" --max-time 15 2>/dev/null \
    > /home/ga/nx_devices.json || echo "[]" > /home/ga/nx_devices.json
chown ga:ga /home/ga/nx_devices.json 2>/dev/null || true

cat > /home/ga/nx_env.sh << ENVEOF
#!/bin/bash
NX_BASE="https://localhost:7001"
NX_ADMIN_PASS="${NX_ADMIN_PASS}"
NX_TOKEN_FILE="/home/ga/nx_token.txt"
ENVEOF
chmod 644 /home/ga/nx_env.sh
chown ga:ga /home/ga/nx_env.sh

# ============================================================
# Step 8: Configure Firefox and open Web Admin
# ============================================================
echo "=== Step 8: Configuring Firefox and opening Web Admin ==="

# Configure Firefox profile for SSL acceptance
# Firefox snap profile path
FF_SNAP_PROFILE=$(find /home/ga/snap/firefox -name "*.default*" -maxdepth 6 -type d 2>/dev/null | head -1 || echo "")
# Fallback: standard profile
if [ -z "$FF_SNAP_PROFILE" ]; then
    FF_SNAP_PROFILE=$(find /home/ga/.mozilla/firefox -name "*.default*" -maxdepth 3 -type d 2>/dev/null | head -1 || echo "")
fi

# Do a warm-up Firefox launch to create profile directory
if ! pgrep -x firefox > /dev/null 2>&1 && ! pgrep -x firefox-esr > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 firefox --headless about:blank &" 2>/dev/null || true
    sleep 8
    pkill -f "firefox.*headless" 2>/dev/null || true
    sleep 3
fi

# Find newly-created profile
FF_SNAP_PROFILE=$(find /home/ga/snap/firefox -name "*.default*" -maxdepth 6 -type d 2>/dev/null | head -1 || \
                  find /home/ga/.mozilla/firefox -name "*.default*" -maxdepth 3 -type d 2>/dev/null | head -1 || echo "")

if [ -n "$FF_SNAP_PROFILE" ]; then
    echo "Configuring Firefox profile: $FF_SNAP_PROFILE"
    cat > "${FF_SNAP_PROFILE}/user.js" << 'USERJS'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutConfig.showWarning", false);
user_pref("security.enterprise_roots.enabled", true);
user_pref("network.stricttransportsecurity.preloadlist", false);
user_pref("security.cert_pinning.enforcement_level", 0);
user_pref("browser.ssl_override_behavior", 2);
user_pref("browser.xul.error_pages.expert_bad_cert", true);
user_pref("security.tls.insecure_fallback_hosts", "localhost");
USERJS
    chown ga:ga "${FF_SNAP_PROFILE}/user.js"
fi

# Launch Firefox with the Nx Witness web admin URL
su - ga -c "DISPLAY=:1 firefox 'https://localhost:7001/static/index.html' &" 2>/dev/null || true
sleep 12

# Accept SSL warning using keyboard navigation (most reliable method).
# The NX Witness cert has SAN=<server-uuid> not localhost, so Firefox always
# shows the SSL warning. Click page body for focus, then Shift+Tab focuses
# "Accept the Risk and Continue" (last tabbable element), Enter clicks it.
DISPLAY=:1 xdotool mousemove 960 400 click 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key shift+Tab 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# If the Advanced section wasn't auto-expanded, the first attempt clicked
# "Advanced..." — now try the accept button again
DISPLAY=:1 xdotool mousemove 960 400 click 1 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key shift+Tab 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Login: triple-click Login field to select any stale text, type credentials
DISPLAY=:1 xdotool mousemove 960 563 click --repeat 3 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "admin" 2>/dev/null || true
sleep 0.3
# Click Password field directly (more reliable than Tab)
DISPLAY=:1 xdotool mousemove 960 637 click 1 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "${NX_ADMIN_PASS}" 2>/dev/null || true
sleep 0.3
# Click "Log In" button directly
DISPLAY=:1 xdotool mousemove 960 690 click 1 2>/dev/null || true
sleep 12

# Dismiss "Save password?" Firefox dialog with Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# ============================================================
# Step 9: Warm-up desktop client to handle first-run dialogs
# ============================================================
echo "=== Step 9: Warming up Nx Witness desktop client ==="

APPLAUNCHER=$(find /opt -name "applauncher" -type f 2>/dev/null | head -1)
if [ -n "$APPLAUNCHER" ]; then
    # Launch client
    DISPLAY=:1 "$APPLAUNCHER" &
    sleep 10

    # Dismiss keyring dialog 1 — "Choose password for new keyring"
    DISPLAY=:1 xdotool mousemove 1060 678 click 1 2>/dev/null || true
    sleep 2

    # Dismiss keyring dialog 2 — "Store passwords unencrypted?"
    DISPLAY=:1 xdotool mousemove 1060 628 click 1 2>/dev/null || true
    sleep 3

    # Dismiss EULA — "I Agree" at actual(1327, 783)
    DISPLAY=:1 xdotool mousemove 1327 783 click 1 2>/dev/null || true
    sleep 5

    # Let welcome screen load
    sleep 3

    # Kill the client (it will start fresh for each task)
    pkill -f "applauncher" 2>/dev/null || true
    pkill -f "client.*networkoptix" 2>/dev/null || true
    sleep 3
    echo "Desktop client warm-up complete, first-run dialogs handled"
else
    echo "WARNING: applauncher not found, skipping client warm-up"
fi

echo "=== Nx Witness VMS setup complete ==="
echo "=== Server: https://localhost:7001 ==="
echo "=== Web Admin: https://localhost:7001/static/index.html ==="
echo "=== Admin: admin / ${NX_ADMIN_PASS} ==="
echo "=== Users: security.operator, camera.admin, site.manager, john.smith, sarah.jones ==="
