#!/bin/bash
# setup_task.sh for osint_media_forensics_capture task
# Prepares Tor Browser, ensures clean target directories, and records baseline state.
set -e
echo "=== Setting up osint_media_forensics_capture task ==="

# 1. Terminate any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# 2. Setup Directories and Remove Stale Evidence Files
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Downloads
rm -f /home/ga/Documents/evidence_media.jpg 2>/dev/null || true
rm -f /home/ga/Documents/forensic_metadata.txt 2>/dev/null || true
rm -f /home/ga/Downloads/*.jpg 2>/dev/null || true
chown -R ga:ga /home/ga/Documents /home/ga/Downloads 2>/dev/null || true

# 3. Reset Tor Browser Profile Security Level and History
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
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        # Reset security level to Standard (removes the Safer/Safest preference)
        sed -i '/browser\.security_level\.security_slider/d' "$PREFS_FILE" 2>/dev/null || true
    fi
    # Clear history and bookmarks for a clean verification slate
    PLACES_DB="$PROFILE_DIR/places.sqlite"
    rm -f "$PLACES_DB" 2>/dev/null || true
    rm -f "$PLACES_DB-shm" 2>/dev/null || true
    rm -f "$PLACES_DB-wal" 2>/dev/null || true
fi

# 4. Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts
echo "Task start timestamp: $(cat /tmp/task_start_ts)"

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

# 6. Wait for Tor Browser window and connection
echo "Waiting for Tor Browser window to appear..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=300
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 10
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Focus and maximize window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== osint_media_forensics_capture task setup complete ==="