#!/bin/bash
# setup_task.sh for configure_onion_client_auth task
# Prepares Tor Browser, clears existing auth keys, and provides the credentials file.

set -e
echo "=== Setting up configure_onion_client_auth task ==="

TASK_NAME="configure_onion_client_auth"

# Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# Locate Tor Browser directories
BASE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        BASE_DIR="$candidate"
        break
    fi
done

if [ -n "$BASE_DIR" ]; then
    PROFILE_DIR="$BASE_DIR/Browser/TorBrowser/Data/Browser/profile.default"
    TOR_DATA_DIR="$BASE_DIR/Browser/TorBrowser/Data/Tor"
    ONION_AUTH_DIR="$TOR_DATA_DIR/onion-auth"
    
    echo "Found Tor Browser base directory: $BASE_DIR"

    # 1. Clean up existing Onion Auth keys
    if [ -d "$ONION_AUTH_DIR" ]; then
        echo "Clearing existing onion auth keys..."
        rm -f "$ONION_AUTH_DIR"/*.auth_private 2>/dev/null || true
    else
        mkdir -p "$ONION_AUTH_DIR"
        chown -R ga:ga "$ONION_AUTH_DIR"
    fi

    # 2. Reset Security Level in prefs.js
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        echo "Resetting security level to standard..."
        sed -i '/browser\.security_level\.security_slider/d' "$PREFS_FILE" 2>/dev/null || true
    fi

    # 3. Clear existing bookmarks to ensure clean state
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    if [ -f "$PLACES_DB" ]; then
        echo "Clearing places.sqlite to remove existing bookmarks..."
        rm -f "$PLACES_DB" "$PLACES_DB-shm" "$PLACES_DB-wal" 2>/dev/null || true
    fi
fi

# Create the credentials file with mock data
sudo -u ga mkdir -p /home/ga/Documents
cat > /home/ga/Documents/source_credentials.txt << 'EOF'
=== CONFIDENTIAL SOURCE CREDENTIALS ===
Please use the Tor Browser to access the secure document dump.
Set your browser security level to SAFEST before connecting.

Target Portal: k53lf57qovyuvwsc6xnrppyply3vtqm7l6pcobkmyqsiofyeznfu5uqd.onion
Auth Type: x25519
Private Key: ORSXG5BRGIZTINJWG44DSNZZHA2TSNRXGI4TINJWG44DSNZZHA2T
=======================================
EOF
chown ga:ga /home/ga/Documents/source_credentials.txt
chmod 600 /home/ga/Documents/source_credentials.txt
echo "Created credentials file at /home/ga/Documents/source_credentials.txt"

# Record task start timestamp
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# Launch Tor Browser
echo "Launching Tor Browser..."
if [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $BASE_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for process
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser process started after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=300
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 10
            TOR_CONNECTED=true
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "WARNING: Tor did not connect within ${TIMEOUT}s. Continuing anyway..."
fi

sleep 5

# Maximize and Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="