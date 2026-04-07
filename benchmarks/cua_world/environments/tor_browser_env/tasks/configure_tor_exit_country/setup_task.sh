#!/bin/bash
echo "=== Setting up configure_tor_exit_country task ==="

# Kill any existing Tor Browser instances for a clean start
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 1

# Ensure target directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/exit_verification.txt
rm -f /home/ga/Documents/tor_exit_config_report.txt
chown -R ga:ga /home/ga/Documents

# Locate Tor Browser paths
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then PROFILE_DIR="$candidate"; break; fi
done

TOR_DATA_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Tor" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Tor" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Tor"
do
    if [ -d "$candidate" ]; then TOR_DATA_DIR="$candidate"; break; fi
done

# Reset torrc to remove any existing ExitNodes configurations
if [ -n "$TOR_DATA_DIR" ] && [ -f "$TOR_DATA_DIR/torrc" ]; then
    sed -i '/^ExitNodes/d' "$TOR_DATA_DIR/torrc" 2>/dev/null || true
    sed -i '/^StrictNodes/d' "$TOR_DATA_DIR/torrc" 2>/dev/null || true
    echo "Reset torrc (removed any existing ExitNodes/StrictNodes)"
fi

# Clear browser history to ensure fresh checks
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    rm -f "$PROFILE_DIR/places.sqlite" "$PROFILE_DIR/places.sqlite-shm" "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
    echo "Cleared browsing history"
fi

# Record task start time (anti-gaming measure)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Launch Tor Browser
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then TOR_BROWSER_DIR="$candidate"; break; fi
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
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser"; then break; fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor connection..."
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
DISPLAY=:1 wmctrl -r "Tor Browser" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="