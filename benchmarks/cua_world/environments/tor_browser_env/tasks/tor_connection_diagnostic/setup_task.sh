#!/bin/bash
# setup_task.sh for tor_connection_diagnostic task
# Prepares Tor Browser environment and ensures a clean state

set -e

echo "=== Setting up tor_connection_diagnostic task ==="

# Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any existing diagnostic report to prevent 'do nothing' gaming
REPORT_PATH="/home/ga/Documents/tor_diagnostic_report.txt"
if [ -f "$REPORT_PATH" ]; then
    echo "Removing stale report file..."
    rm -f "$REPORT_PATH"
fi

# Find Tor Browser profile directory to clear history
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

# Clear browsing history to ensure clean test
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    echo "Clearing history database..."
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
fi

# Record task start timestamp for verification
TASK_START_TIMESTAMP=$(date +%s)
echo "$TASK_START_TIMESTAMP" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START_TIMESTAMP"

# Launch Tor Browser
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

# Wait for Tor Browser to start
echo "Waiting for Tor Browser process..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser started after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for window to appear
echo "Waiting for Tor Browser window..."
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        echo "Window appeared after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Focus and maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="