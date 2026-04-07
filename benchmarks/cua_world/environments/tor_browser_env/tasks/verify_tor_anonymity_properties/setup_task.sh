#!/bin/bash
set -e
echo "=== Setting up verify_tor_anonymity_properties task ==="

TASK_NAME="verify_tor_anonymity_properties"

# Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# Clean up target file
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/anonymity-verification.txt 2>/dev/null || true
chown ga:ga /home/ga/Documents 2>/dev/null || true

# Find Tor Browser profile and clear history
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
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
fi

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

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

if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for process and window
ELAPSED=0
while [ $ELAPSED -lt 30 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for connection
ELAPSED=0
while [ $ELAPSED -lt 120 ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 5

WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete ==="