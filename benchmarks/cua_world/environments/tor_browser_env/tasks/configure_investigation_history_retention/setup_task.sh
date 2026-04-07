#!/bin/bash
# setup_task.sh - Pre-task hook for configure_investigation_history_retention

set -e
echo "=== Setting up configure_investigation_history_retention task ==="

TASK_NAME="configure_investigation_history_retention"

# 1. Kill any existing Tor Browser instances
echo "Killing existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# 2. Locate Tor Browser profile
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

# 3. Wipe any existing history and reset prefs to Tor defaults
if [ -n "$PROFILE_DIR" ]; then
    echo "Wiping places.sqlite to ensure clean history state..."
    rm -f "$PROFILE_DIR/places.sqlite" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
    rm -f "$PROFILE_DIR/places.sqlite-shm" 2>/dev/null || true
    
    PREFS_FILE="$PROFILE_DIR/prefs.js"
    if [ -f "$PREFS_FILE" ]; then
        echo "Resetting privacy preferences to default amnesic state..."
        sed -i '/browser\.privatebrowsing\.autostart/d' "$PREFS_FILE" 2>/dev/null || true
        sed -i '/privacy\.sanitize\.sanitizeOnShutdown/d' "$PREFS_FILE" 2>/dev/null || true
    fi
fi

# 4. Record task start timestamp for anti-gaming (comparing with visit times)
date +%s > "/tmp/${TASK_NAME}_start_ts"
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# 5. Provide instructions on desktop
cat > /home/ga/Desktop/TASK_INSTRUCTIONS.txt << 'EOF'
TASK: Configure Investigation History Retention

1. Open Tor Browser Settings -> Privacy & Security.
2. Under "History", select "Use custom settings for history".
3. Uncheck "Always use private browsing mode" and Restart Tor Browser.
4. After restart, go back to Settings -> Privacy & Security -> History.
5. Uncheck "Clear history when Tor Browser closes".
6. Visit https://check.torproject.org/ and https://duckduckgo.com/.
7. Close Tor Browser completely to sync databases to disk.
EOF
chmod 644 /home/ga/Desktop/TASK_INSTRUCTIONS.txt

# 6. Launch Tor Browser
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
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        echo "Tor Browser window appeared."
        break
    fi
    sleep 1
done

# Wait for Tor connection (avoid interacting while it's establishing circuit)
echo "Waiting for Tor connection to establish..."
for i in {1..60}; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting"; then
        echo "Tor connected."
        break
    fi
    sleep 2
done

# Focus the window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="