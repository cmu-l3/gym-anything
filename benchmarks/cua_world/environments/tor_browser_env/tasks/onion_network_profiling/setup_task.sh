#!/bin/bash
# setup_task.sh for onion_network_profiling
set -e

echo "=== Setting up onion_network_profiling task ==="

# Clean up any existing Tor Browser instances
echo "Killing existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# Prepare target directory
echo "Preparing output directory..."
sudo -u ga mkdir -p /home/ga/Documents/OnionProfiling
# Remove any existing HAR files to ensure a clean slate
rm -f /home/ga/Documents/OnionProfiling/*.har 2>/dev/null || true

# Record task start timestamp for anti-gaming validation
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
    echo "WARNING: Tor did not reliably connect within ${TIMEOUT}s, proceeding anyway"
else
    echo "Tor Browser connected successfully."
fi

# Maximize the Tor Browser window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Allow UI to stabilize
sleep 3

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== onion_network_profiling task setup complete ==="