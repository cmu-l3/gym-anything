#!/bin/bash
# setup_task.sh for document_handling_opsec_hardening task
# Prepares Tor Browser, resets relevant preferences, and cleans up target directories.

set -e
echo "=== Setting up document_handling_opsec_hardening task ==="

TASK_NAME="document_handling_opsec_hardening"

# 1. Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# 2. Find Tor Browser profile
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

PREFS_FILE="$PROFILE_DIR/prefs.js"
PLACES_DB="$PROFILE_DIR/places.sqlite"

# 3. Clean environment (anti-gaming & baseline setup)
# Clear places history
if [ -n "$PROFILE_DIR" ] && [ -f "$PLACES_DB" ]; then
    echo "Clearing browsing history..."
    rm -f "$PLACES_DB" 2>/dev/null || true
    rm -f "${PLACES_DB}-shm" 2>/dev/null || true
    rm -f "${PLACES_DB}-wal" 2>/dev/null || true
fi

# Remove the specific prefs we will test to force agent to set them
if [ -n "$PROFILE_DIR" ] && [ -f "$PREFS_FILE" ]; then
    echo "Resetting target privacy/rendering prefs to default..."
    sed -i '/user_pref("pdfjs\.disabled"/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/user_pref("webgl\.disabled"/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/user_pref("javascript\.options\.wasm"/d' "$PREFS_FILE" 2>/dev/null || true
fi

# Clean up any previously created files/directories
rm -rf /home/ga/Documents/Quarantine 2>/dev/null || true
rm -f /home/ga/Downloads/rfc8446.txt.pdf 2>/dev/null || true
rm -f /home/ga/Downloads/rfc8446.pdf 2>/dev/null || true

# 4. Record task start timestamp (after cleanups)
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# 5. Launch Tor Browser
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

# Wait for process and window
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser process started"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting|download"; then
        echo "Tor Browser window visible"
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
    echo "ERROR: Tor Browser did not connect within ${TIMEOUT}s"
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_failed.png 2>/dev/null || true
    # We proceed anyway so the agent can attempt recovery/diagnosis if capable
fi

sleep 5

# Focus window and maximize
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="