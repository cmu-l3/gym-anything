#!/bin/bash
# setup_task.sh for first_party_circuit_isolation_audit
# Prepares clean Tor Browser state, fetches clearnet IP, and launches browser

set -e
echo "=== Setting up first_party_circuit_isolation_audit task ==="

TASK_NAME="first_party_circuit_isolation_audit"

# 1. Kill any existing Tor Browser instances
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# 2. Get the environment's clearnet IP (before using Tor) to verify Tor routing later
echo "Fetching clear-net IP..."
curl -s --max-time 10 https://api.ipify.org > /tmp/clearnet_ip.txt 2>/dev/null || echo "unknown" > /tmp/clearnet_ip.txt
echo "Clear-net IP recorded: $(cat /tmp/clearnet_ip.txt)"

# 3. Ensure Documents directory exists and remove any old artifacts
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/isolation_audit.json 2>/dev/null || true
chown ga:ga /home/ga/Documents 2>/dev/null || true

# 4. Find Tor Browser profile and clear history (preventing history gaming)
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done

if [ -n "$PROFILE_DIR" ]; then
    echo "Clearing Tor Browser history for clean test state..."
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
fi

# Record task start timestamp (after cleanup)
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

echo "Launching Tor Browser..."
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# 6. Wait for window and maximize
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        echo "Tor Browser window detected"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Focus and maximize
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser|connecting" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="