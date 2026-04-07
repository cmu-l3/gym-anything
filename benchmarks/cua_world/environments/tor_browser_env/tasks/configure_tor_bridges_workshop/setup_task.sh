#!/bin/bash
set -e
echo "=== Setting up configure_tor_bridges_workshop task ==="

TASK_NAME="configure_tor_bridges_workshop"

# Kill existing Tor Browsers
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# Find Profile Directory to clean up state
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
    echo "Cleaning up history and bridge configurations..."
    # Clear history and bookmarks
    rm -f "$PROFILE_DIR/places.sqlite"* 2>/dev/null || true
    
    # Remove bridge settings
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        sed -i '/bridges\.enabled/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/bridges\.source/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/bridges\.builtin_type/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/extensions\.torlauncher/d' "$PREFS_FILE" 2>/dev/null || true
    fi
    
    # Check torrc
    TORRC_FILE="$PROFILE_DIR/../Tor/torrc"
    if [ -f "$TORRC_FILE" ]; then
        sed -i '/UseBridges/d' "$TORRC_FILE" 2>/dev/null || true
        sed -i '/ClientTransportPlugin/d' "$TORRC_FILE" 2>/dev/null || true
    fi
fi

# Clean up target markdown document
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/bridge-workshop-guide.md 2>/dev/null || true
chown ga:ga /home/ga/Documents 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

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

# Wait for process and window
ELAPSED=0
while [ $ELAPSED -lt 60 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 3

# Maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser|connecting" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="