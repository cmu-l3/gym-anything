#!/bin/bash
set -e
echo "=== Setting up export_pages_as_pdf task ==="

# Record task start time (for anti-gaming timestamp verification)
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp: $(cat /tmp/task_start_time.txt)"

# Ensure Documents directory exists and remove any stale target PDFs
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/tor_history.pdf
rm -f /home/ga/Documents/tor_support_about.pdf
rm -f /home/ga/Documents/tor_training_risks.pdf
chown -R ga:ga /home/ga/Documents

# Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2

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
        echo "Tor Browser process started"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for window
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        echo "Tor Browser window appeared"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor network connection..."
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
    echo "WARNING: Tor did not connect within ${TIMEOUT}s. The agent will have to connect manually."
else
    echo "Tor is connected."
fi

sleep 5

# Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

sleep 2
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="