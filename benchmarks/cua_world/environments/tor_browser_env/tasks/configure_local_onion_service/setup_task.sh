#!/bin/bash
echo "=== Setting up configure_local_onion_service task ==="

TASK_NAME="configure_local_onion_service"

# Kill existing Tor Browser
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2

# Cleanup previous state if any
rm -rf /home/ga/Documents/local_onion/ 2>/dev/null || true
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Setup local web server on 8080
mkdir -p /tmp/local_web_root
cat > /tmp/local_web_root/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Secure Drop Site Test</title></head>
<body><h1>Secure Drop Site Test</h1><p>If you see this over an onion address, your hidden service is working.</p></body>
</html>
EOF

# Kill any existing python http server on 8080
fuser -k 8080/tcp 2>/dev/null || true
sleep 1

# Start python http server in background
sudo -u ga bash -c "cd /tmp/local_web_root && python3 -m http.server 8080 > /dev/null 2>&1 &"

# Launch Tor Browser once to ensure profile and torrc are generated
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

echo "Launching Tor Browser to generate profile..."
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# Wait for Tor Browser and torrc to be created
echo "Waiting for Tor Browser torrc to be generated..."
ELAPSED=0
TIMEOUT=60
TORRC_PATH=""
while [ $ELAPSED -lt $TIMEOUT ]; do
    for candidate in \
        "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Tor/torrc" \
        "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Tor/torrc" \
        "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Tor/torrc"
    do
        if [ -f "$candidate" ]; then
            TORRC_PATH="$candidate"
            break
        fi
    done
    if [ -n "$TORRC_PATH" ]; then
        echo "Found torrc at $TORRC_PATH"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED+2))
done

# Ensure torrc is clean of HiddenService directives from past tasks
if [ -n "$TORRC_PATH" ]; then
    sed -i '/HiddenServiceDir/d' "$TORRC_PATH" 2>/dev/null || true
    sed -i '/HiddenServicePort/d' "$TORRC_PATH" 2>/dev/null || true
fi

# Wait for window to appear
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Wait for Tor connection so agent starts from a fully booted state
echo "Waiting for Tor connection..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if [ -n "$WINDOW_TITLE" ] && ! echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 5
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

date +%s > /tmp/${TASK_NAME}_start_ts

# Focus window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
[ -n "$WINDOW_ID" ] && DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
[ -n "$WINDOW_ID" ] && DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== setup_task complete ==="