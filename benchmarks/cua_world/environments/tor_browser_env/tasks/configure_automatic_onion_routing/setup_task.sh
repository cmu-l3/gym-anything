#!/bin/bash
# setup_task.sh for configure_automatic_onion_routing task
set -e

echo "=== Setting up automatic onion routing task ==="

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure documents directory exists and clean old files
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/onion_routing_report.txt 2>/dev/null || true

# Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true

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

# Reset places and preferences
if [ -n "$PROFILE_DIR" ]; then
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    PLACES_DB="$PROFILE_DIR/places.sqlite"

    # Remove the prioritizeonions preference to ensure agent has to set it
    if [ -f "$PREFS_FILE" ]; then
        sed -i '/privacy\.prioritizeonions\.enabled/d' "$PREFS_FILE" 2>/dev/null || true
        echo "Cleared prioritizeonions setting from prefs.js"
    fi

    # Clear history to avoid false positives
    if [ -f "$PLACES_DB" ]; then
        rm -f "$PLACES_DB" "$PLACES_DB-shm" "$PLACES_DB-wal" 2>/dev/null || true
        echo "Cleared places.sqlite database"
    fi
fi

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
ELAPSED=0
while [ $ELAPSED -lt 30 ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        echo "Tor Browser window detected."
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor connection..."
ELAPSED=0
while [ $ELAPSED -lt 120 ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Maximize Window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# Initial Screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="