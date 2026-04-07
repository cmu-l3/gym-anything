#!/bin/bash
# setup_task.sh for configure_corporate_proxy_routing
# Prepares Tor Browser, ensures a clean state, and creates the briefing document.

set -e
echo "=== Setting up configure_corporate_proxy_routing task ==="

TASK_NAME="configure_corporate_proxy_routing"

# 1. Kill any existing Tor Browser instances for a clean start
echo "Killing existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 2

# 2. Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# 3. Clean up any previous task artifacts
rm -f /home/ga/Documents/torrc_backup.txt 2>/dev/null || true

# 4. Create the realistic Network Briefing Document
echo "Creating Network Briefing document..."
cat > /home/ga/Documents/Network_Briefing.md << 'EOF'
# IT Security Briefing - Corporate Network Transition
**Date:** October 12, 2025
**To:** All Intelligence Analysts
**Subject:** Mandatory Secure Web Gateway (SWG) Routing for Tor Traffic

Due to recent network security policy updates, direct outbound Tor connections are no longer permitted from analyst workstations. Our perimeter firewall will now drop all standard Tor directory and relay traffic.

To continue Open Source Intelligence (OSINT) gathering via Tor Browser, you must route your browser's initial connections through the internal corporate Secure Web Gateway (SWG).

### Required Proxy Configuration Details:
Please update your Tor Browser Connection Settings immediately with the following parameters:
- **Proxy Type:** HTTP/HTTPS
- **Address:** 10.200.5.99
- **Port:** 8080

*Note: You must configure this in Tor Browser's native Connection Settings (Settings -> Connection -> Advanced -> Settings). Do not modify system-wide proxy settings.*

### Compliance Requirement
After applying these settings, you must create a backup of your active `torrc` configuration file to prove compliance with the new architecture. 
Save the backup file exactly to:
`/home/ga/Documents/torrc_backup.txt`
EOF
chown ga:ga /home/ga/Documents/Network_Briefing.md

# 5. Find Tor Browser and reset torrc to ensure no proxy is currently set
TOR_BROWSER_DIR=""
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        PROFILE_DIR="$candidate/Browser/TorBrowser/Data"
        break
    fi
done

if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/Tor/torrc" ]; then
    echo "Resetting active torrc file..."
    # Remove any existing proxy directives to prevent false positives
    sed -i '/HTTPSProxy/d' "$PROFILE_DIR/Tor/torrc" 2>/dev/null || true
    sed -i '/Socks4Proxy/d' "$PROFILE_DIR/Tor/torrc" 2>/dev/null || true
    sed -i '/Socks5Proxy/d' "$PROFILE_DIR/Tor/torrc" 2>/dev/null || true
fi

# 6. Record task start timestamp (crucial for anti-gaming)
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# 7. Launch Tor Browser
echo "Launching Tor Browser from: $TOR_BROWSER_DIR"
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# 8. Wait for Tor Browser window and maximize it
echo "Waiting for Tor Browser window..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | awk '{print $1}')
    if [ -n "$WINDOW_ID" ]; then
        echo "Tor Browser window appeared after ${ELAPSED}s"
        DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="