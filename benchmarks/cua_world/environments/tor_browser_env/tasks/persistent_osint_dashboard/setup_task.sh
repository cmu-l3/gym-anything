#!/bin/bash
# setup_task.sh for persistent_osint_dashboard
set -e

echo "=== Setting up persistent_osint_dashboard task ==="

TASK_NAME="persistent_osint_dashboard"

# Record task start timestamp (anti-gaming)
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# 1. Kill any existing Tor Browser instances
echo "Killing existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# 2. Clean up any existing artifacts
echo "Cleaning up potential artifacts from previous runs..."
rm -f /home/ga/Documents/osint_dashboard.html 2>/dev/null || true
rm -f /home/ga/Desktop/OSINT-Dashboard.desktop 2>/dev/null || true
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 3. Find Tor Browser profile and reset to amnesic baseline
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

if [ -n "$PROFILE_DIR" ]; then
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        echo "Resetting private browsing to true (amnesic mode)..."
        # Remove any existing line setting this preference
        sed -i '/browser\.privatebrowsing\.autostart/d' "$PREFS_FILE" 2>/dev/null || true
        # Force it to true so the agent has to change it
        echo 'user_pref("browser.privatebrowsing.autostart", true);' >> "$PREFS_FILE"
    fi

    # Clear history database to ensure clean state
    echo "Clearing places.sqlite to ensure clean history baseline..."
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
fi

# 4. Launch Tor Browser so the agent doesn't start from an empty desktop
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
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser_setup.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser_setup.log 2>&1 &"
fi

# Wait for window to appear
echo "Waiting for Tor Browser window..."
ELAPSED=0
TIMEOUT=60
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Maximize and focus Tor Browser
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Capture initial screenshot
sleep 1
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== setup_task.sh complete ==="