#!/bin/bash
# setup_task.sh for configure_legacy_http_portal_exception
# Cleans the environment, clears prior DBs, and launches Tor Browser

set -e
echo "=== Setting up configure_legacy_http_portal_exception task ==="

TASK_NAME="configure_legacy_http_portal_exception"

# Kill any existing Tor Browser instances
echo "Killing existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true

# Find Tor Browser profile directory
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Found Tor Browser profile at: $PROFILE_DIR"
        break
    fi
done

# Clear databases to ensure clean slate for verification
if [ -n "$PROFILE_DIR" ]; then
    echo "Clearing permissions and history databases..."
    rm -f "$PROFILE_DIR/permissions.sqlite"* 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite"* 2>/dev/null || true
fi

# Ensure documents dir and clean evidence file
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/neverssl_evidence.txt 2>/dev/null || true

# Write task instructions for the agent's convenience
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: Configure Legacy HTTP Portal Exception

An intelligence analyst is monitoring a legacy foreign government portal that only supports unencrypted HTTP. Because Tor Browser enforces HTTPS globally, you must configure a permanent exception for this specific domain.

1. Open Tor Browser Settings and navigate to the Privacy & Security panel.
2. Scroll to the 'HTTPS-Only Mode' section.
3. Click 'Manage Exceptions...' and add 'neverssl.com' (or 'http://neverssl.com') to the exception list with the status 'Off' (allowing insecure connections permanently).
4. Navigate to 'http://neverssl.com' in the URL bar. It should load directly without displaying the 'Secure Connection Not Available' warning screen.
5. Copy the main text content from the NeverSSL page.
6. Create a plain text file at '/home/ga/Documents/neverssl_evidence.txt' and paste the copied text into it. Ensure it contains the word 'NeverSSL'.
EOF
chown ga:ga /home/ga/TASK_INFO.txt

# Record task start timestamp (anti-gaming check)
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# Find and launch Tor Browser
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

echo "Launching Tor Browser..."
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
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
    if echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        :
    elif [ -n "$WINDOW_TITLE" ]; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            echo "Tor Browser connected after ${ELAPSED}s"
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 10
            WINDOW_TITLE_RECHECK=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
            if ! echo "$WINDOW_TITLE_RECHECK" | grep -qiE "connecting|establishing"; then
                TOR_CONNECTED=true
                break
            fi
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "Still waiting for Tor connection... (${ELAPSED}s)"
    fi
done

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "ERROR: Tor did not connect within ${TIMEOUT}s"
    exit 1
fi

sleep 10

# Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
[ -n "$WINDOW_ID" ] && DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== setup complete ==="