#!/bin/bash
# setup_task.sh - Pre-task hook for configure_tls_interception_and_hardening
# Generates the Proxy CA, resets preferences, and prepares the browser

set -e
echo "=== Setting up configure_tls_interception_and_hardening task ==="

# 1. Install required dependencies for NSS database verification
export DEBIAN_FRONTEND=noninteractive
apt-get update -yq && apt-get install -yq libnss3-tools openssl

# 2. Kill any existing Tor Browser instances
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true

# 3. Create the Documents directory and generate the ProxyRootCA
sudo -u ga mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/ProxyRootCA.*
rm -f /home/ga/Documents/ISRG_Root_Backup.crt

echo "Generating custom ProxyRootCA..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /home/ga/Documents/ProxyRootCA.key \
    -out /home/ga/Documents/ProxyRootCA.crt \
    -subj "/C=US/ST=State/L=City/O=Test Proxy Org/OU=Security/CN=ProxyRootCA" 2>/dev/null

chown ga:ga /home/ga/Documents/ProxyRootCA.*

# 4. Find Tor Browser profile and reset relevant preferences
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

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/prefs.js" ]; then
    echo "Resetting targeted preferences in prefs.js..."
    sed -i '/security\.tls\.version\.min/d' "$PROFILE_DIR/prefs.js" 2>/dev/null || true
    sed -i '/security\.cert_pinning\.enforcement_level/d' "$PROFILE_DIR/prefs.js" 2>/dev/null || true
fi

# 5. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_time
echo "Task start timestamp: $(cat /tmp/task_start_time)"

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

# Wait for window
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting"; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# Maximize Tor Browser window
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

sleep 2

# 7. Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="