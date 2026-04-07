#!/bin/bash
# setup_task.sh for configure_persistent_download_workflow task
# Prepares clean state: removes target directory, resets prefs, clears history

set -e
echo "=== Setting up configure_persistent_download_workflow task ==="

TASK_NAME="configure_persistent_download_workflow"

# Kill any existing Tor Browser instances
echo "Killing existing Tor Browser processes..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# Clean up any previous task artifacts
echo "Cleaning up directories and files..."
rm -rf /home/ga/Documents/SecureDownloads 2>/dev/null || true
rm -f /home/ga/Downloads/tor_check.html /home/ga/Downloads/tor_manual.html /home/ga/Downloads/tor_specs.html 2>/dev/null || true

# Find Tor Browser profile
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

# Reset preferences and history
if [ -n "$PROFILE_DIR" ]; then
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        echo "Resetting download preferences..."
        sed -i '/browser\.download\.dir/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/browser\.download\.folderList/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/browser\.download\.useDownloadDir/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/browser\.download\.lastDir/d' "$PREFS_FILE" 2>/dev/null || true
    fi

    PLACES_DB="$PROFILE_DIR/places.sqlite"
    if [ -f "$PLACES_DB" ]; then
        echo "Clearing browsing history..."
        rm -f "$PLACES_DB" 2>/dev/null || true
        rm -f "$PLACES_DB-shm" 2>/dev/null || true
        rm -f "$PLACES_DB-wal" 2>/dev/null || true
    fi
fi

# Record task start timestamp (AFTER cleanup)
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

# Wait for process and window
echo "Waiting for Tor Browser window..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting|download"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor connection..."
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
    echo "ERROR: Tor did not connect within ${TIMEOUT}s"
fi

sleep 5

# Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
[ -n "$WINDOW_ID" ] && DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true

sleep 2
# Take initial screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="