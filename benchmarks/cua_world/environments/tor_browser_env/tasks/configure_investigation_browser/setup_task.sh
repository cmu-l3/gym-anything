#!/bin/bash
# setup_task.sh - Pre-task hook for configure_investigation_browser
# Prepares Tor Browser in a clean default state

set -e
echo "=== Setting up configure_investigation_browser task ==="

TASK_NAME="configure_investigation_browser"

# 1. Clean up existing Tor processes
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# 2. Find Tor Browser profile directory
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

# 3. Reset databases and preferences to ensure a clean slate
if [ -n "$PROFILE_DIR" ]; then
    echo "Resetting databases and preferences to baseline..."
    
    # Remove existing permissions (cookies/popups exceptions)
    rm -f "$PROFILE_DIR/permissions.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/permissions.sqlite-wal" 2>/dev/null || true
    rm -f "$PROFILE_DIR/permissions.sqlite-shm" 2>/dev/null || true
    
    # Remove existing history
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    
    # Reset prefs.js
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        sed -i '/dom\.webnotifications\.enabled/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/browser\.startup\.page/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/browser\.startup\.homepage/d' "$PREFS_FILE" 2>/dev/null || true
    fi
fi

# 4. Prepare file system requirements
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/investigation_prep.txt 2>/dev/null || true

# 5. Record start time (for anti-gaming validation)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $TASK_START"

# 6. Find and launch Tor Browser
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

echo "Launching Tor Browser from: $TOR_BROWSER_DIR"
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for process and connection
echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=180
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
    echo "WARNING: Tor Browser may not have connected within ${TIMEOUT}s. Proceeding anyway."
else
    echo "Tor Browser connected successfully."
fi

# Ensure window is maximized and focused
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Capture initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== setup_task.sh complete ==="