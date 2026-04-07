#!/bin/bash
set -e
echo "=== Setting up configure_localhost_dev_bypass task ==="

# Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
sleep 1

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

# Reset network proxy preferences to ensure a clean slate
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    echo "Resetting localhost hijacking preferences to defaults..."
    sed -i '/network\.proxy\.allow_hijacking_localhost/d' "$PROFILE_DIR/prefs.js" 2>/dev/null || true
    sed -i '/network\.proxy\.no_proxies_on/d' "$PROFILE_DIR/prefs.js" 2>/dev/null || true
fi

# Clear history to avoid false positives for visited URL
if [ -n "$PROFILE_DIR" ]; then
    rm -f "$PROFILE_DIR/places.sqlite"* 2>/dev/null || true
fi

# Clean up target file in case of reruns
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/tor_headers.txt 2>/dev/null || true
chown ga:ga /home/ga/Documents 2>/dev/null || true

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task start timestamp: $(cat /tmp/task_start_time)"

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

# Wait for Tor Browser window to appear
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting|download"; then
        echo "Tor Browser window detected"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Give the browser time to render
sleep 5

# Maximize and Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="