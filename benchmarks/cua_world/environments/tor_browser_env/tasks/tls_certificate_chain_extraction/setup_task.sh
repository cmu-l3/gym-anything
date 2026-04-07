#!/bin/bash
echo "=== Setting up tls_certificate_chain_extraction task ==="

# Source utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# Kill any existing Tor Browser instances for a clean start
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true

# Clean up any existing target files to prevent false positives
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga rm -f /home/ga/Documents/target_cert_chain.pem
sudo -u ga rm -f /home/ga/Documents/cert_viewer_screenshot.png

# Record task start timestamp for anti-gaming verification
TASK_START_TIMESTAMP=$(date +%s)
echo "$TASK_START_TIMESTAMP" > /tmp/task_start_timestamp

# Create task info file
cat > /home/ga/TASK_INFO.txt << 'EOF'
TASK: TLS Certificate Chain Extraction

1. Open Tor Browser and visit https://community.torproject.org/
2. Open the Certificate Viewer for this website
3. Download the full certificate chain (PEM format)
4. Save/move it to exactly: /home/ga/Documents/target_cert_chain.pem
5. Take a screenshot of the Certificate Viewer and save it to: /home/ga/Documents/cert_viewer_screenshot.png
EOF
chown ga:ga /home/ga/TASK_INFO.txt

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
TIMEOUT=60
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection
echo "Waiting for Tor connection..."
ELAPSED=0
TIMEOUT=180
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting"; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 5
            TOR_CONNECTED=true
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "WARNING: Tor did not fully connect within ${TIMEOUT}s, proceeding anyway."
fi

# Maximize Tor Browser window to ensure UI elements are visible
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

sleep 2

# Take initial screenshot to prove starting state
DISPLAY=:1 import -window root /tmp/task_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup complete ==="