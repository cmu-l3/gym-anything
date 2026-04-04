#!/bin/bash
# set -euo pipefail

echo "=== Setting up Google Chrome configuration ==="

# Set up Chrome for a specific user
setup_user_chrome() {
    local username=$1
    local home_dir=$2
    local remote_debugging_port=${3:-1337}
    
    echo "Setting up Chrome for user: $username (debugging port: $remote_debugging_port)"
    
    # Create Chrome config directory
    sudo -u $username mkdir -p "$home_dir/.config/google-chrome/Default"
    sudo -u $username mkdir -p "$home_dir/.config/google-chrome/Profile 1"
    sudo -u $username mkdir -p "$home_dir/.config/google-chrome-cdp"
    sudo -u $username mkdir -p "$home_dir/Downloads"
    sudo -u $username mkdir -p "$home_dir/Desktop"
    
    # Copy custom Chrome preferences if available
    if [ -f "/workspace/config/chrome_preferences.json" ]; then
        sudo -u $username cp "/workspace/config/chrome_preferences.json" "$home_dir/.config/google-chrome/Default/Preferences"
        echo "  - Copied custom preferences"
    else
        # Create default preferences with CDP support and useful settings
        cat > "$home_dir/.config/google-chrome/Default/Preferences" << 'PREFEOF'
{
   "profile": {
      "default_content_setting_values": {
         "notifications": 2,
         "geolocation": 2
      },
      "password_manager_enabled": false
   },
   "browser": {
      "show_home_button": true,
      "check_default_browser": false
   },
   "download": {
      "prompt_for_download": false,
      "directory_upgrade": true
   },
   "safebrowsing": {
      "enabled": false
   },
   "credentials_enable_service": false,
   "translate": {
      "enabled": false
   }
}
PREFEOF
        chown $username:$username "$home_dir/.config/google-chrome/Default/Preferences"
        echo "  - Created default preferences"
    fi
    
    # Create bookmarks structure
    cat > "$home_dir/.config/google-chrome/Default/Bookmarks" << 'BOOKEOF'
{
   "checksum": "0000000000000000000000000000000000000000",
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "13000000000000000",
         "date_modified": "0",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13000000000000000",
         "date_modified": "0",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13000000000000000",
         "date_modified": "0",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
BOOKEOF
    chown $username:$username "$home_dir/.config/google-chrome/Default/Bookmarks"
    echo "  - Created bookmarks structure"
    
    # Set up desktop shortcut (will use the launch script)
    cat > "$home_dir/Desktop/Chrome.desktop" << DESKTOPEOF
[Desktop Entry]
Name=Chrome Browser
Comment=Access the Internet
Exec=$home_dir/launch_chrome.sh %U
Icon=chromium-browser
StartupNotify=true
Terminal=false
MimeType=text/html;text/xml;application/xhtml_xml;image/webp;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;
Categories=Network;WebBrowser;
Type=Application
DESKTOPEOF
    chown $username:$username "$home_dir/Desktop/Chrome.desktop"
    chmod +x "$home_dir/Desktop/Chrome.desktop"
    echo "  - Created desktop shortcut"
    
    # Create launch script with CDP enabled
    cat > "$home_dir/launch_chrome.sh" << 'LAUNCHEOF'
#!/bin/bash
# Launch Chrome with remote debugging enabled
export DISPLAY=${DISPLAY:-:1}

# Ensure proper permissions for X11
xhost +local: 2>/dev/null || true

# Detect which browser to use
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
elif command -v chrome-browser &> /dev/null; then
    CHROME_CMD="chrome-browser"
else
    echo "ERROR: No Chrome/Chromium browser found!"
    exit 1
fi

# Create a dedicated user data directory for CDP (non-default location required)
CDP_USER_DATA_DIR="$HOME/.config/google-chrome-cdp"
mkdir -p "$CDP_USER_DATA_DIR"

# Launch Chrome with remote debugging
$CHROME_CMD \
    --remote-debugging-port=PORT_PLACEHOLDER \
    --remote-debugging-address=0.0.0.0 \
    --user-data-dir=$CDP_USER_DATA_DIR \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --disable-client-side-phishing-detection \
    --disable-component-update \
    --disable-default-apps \
    --disable-hang-monitor \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --disable-sync \
    --disable-web-resources \
    --enable-automation \
    --password-store=basic \
    --use-mock-keychain \
    --no-sandbox \
    --disable-session-crashed-bubble \
    --hide-crash-restore-bubble \
    --disable-http2 \
    --disable-quic \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-software-rasterizer \
    --window-size=1920,1080 \
    --force-device-scale-factor=1 \
    --disable-blink-features=AutomationControlled \
    --disable-infobars \
    "$@" > /tmp/chrome_$USER.log 2>&1 &

echo "Chrome started with remote debugging on port PORT_PLACEHOLDER"
echo "Log file: /tmp/chrome_$USER.log"
LAUNCHEOF
    # Replace placeholder with actual port
    sed -i "s/PORT_PLACEHOLDER/$remote_debugging_port/g" "$home_dir/launch_chrome.sh"
    chown $username:$username "$home_dir/launch_chrome.sh"
    chmod +x "$home_dir/launch_chrome.sh"
    echo "  - Created launch script with CDP support"
}

# Setup for ga user (the main VNC user)
if id "ga" &>/dev/null; then
    setup_user_chrome "ga" "/home/ga" 1337
fi

# Setup for webuser
if id "webuser" &>/dev/null; then
    setup_user_chrome "webuser" "/home/webuser" 1338
fi

# Set up socat for port forwarding (CDP access from host)
# This forwards the standard CDP port 9222 to the actual debugging port
echo "Setting up socat for CDP port forwarding..."
cat > /usr/local/bin/start-cdp-proxy << 'SOCATEOF'
#!/bin/bash
# Start socat proxy for Chrome DevTools Protocol
# This allows external access to Chrome's remote debugging port

# Kill any existing socat processes on these ports
pkill -f "socat.*9222" || true

# Start socat to forward 9222 to 1337 (ga user's Chrome)
socat tcp-listen:9222,fork,reuseaddr tcp:localhost:1337 > /tmp/socat_cdp.log 2>&1 &

echo "CDP proxy started: 9222 -> 1337"
echo "Log: /tmp/socat_cdp.log"
SOCATEOF
chmod +x /usr/local/bin/start-cdp-proxy

# Start the CDP proxy
/usr/local/bin/start-cdp-proxy || true
sleep 1

# Create CDP utility scripts for verifiers
cat > /usr/local/bin/chrome-cdp-util << 'CDPUTILEOF'
#!/usr/bin/env python3
"""
Chrome DevTools Protocol utility for verification tasks
Provides helper functions to interact with Chrome via CDP
"""
import json
import sys
import argparse
import requests
from urllib.parse import urlparse

def get_tabs(port=9222, host='localhost'):
    """Get all open tabs"""
    try:
        response = requests.get(f'http://{host}:{port}/json')
        return response.json()
    except Exception as e:
        print(f"Error getting tabs: {e}", file=sys.stderr)
        return []

def get_active_tab(port=9222, host='localhost'):
    """Get the currently active tab"""
    tabs = get_tabs(port, host)
    for tab in tabs:
        if tab.get('type') == 'page' and 'url' in tab:
            return tab
    return None if not tabs else tabs[0]

def get_tab_url(port=9222, host='localhost'):
    """Get the URL of the active tab"""
    tab = get_active_tab(port, host)
    return tab.get('url', '') if tab else ''

def get_tab_title(port=9222, host='localhost'):
    """Get the title of the active tab"""
    tab = get_active_tab(port, host)
    return tab.get('title', '') if tab else ''

def list_all_tabs(port=9222, host='localhost'):
    """List all tabs with their URLs"""
    tabs = get_tabs(port, host)
    result = []
    for tab in tabs:
        if tab.get('type') == 'page':
            result.append({
                'url': tab.get('url', ''),
                'title': tab.get('title', ''),
                'id': tab.get('id', '')
            })
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Chrome CDP Utility')
    parser.add_argument('command', choices=['active-url', 'active-tab', 'list-tabs', 'tabs-json'])
    parser.add_argument('--port', type=int, default=9222)
    parser.add_argument('--host', default='localhost')
    args = parser.parse_args()
    
    if args.command == 'active-url':
        print(get_tab_url(args.port, args.host))
    elif args.command == 'active-tab':
        tab = get_active_tab(args.port, args.host)
        print(json.dumps(tab, indent=2))
    elif args.command == 'list-tabs':
        tabs = list_all_tabs(args.port, args.host)
        for i, tab in enumerate(tabs):
            print(f"{i+1}. [{tab['title']}] {tab['url']}")
    elif args.command == 'tabs-json':
        tabs = list_all_tabs(args.port, args.host)
        print(json.dumps(tabs, indent=2))
CDPUTILEOF
chmod +x /usr/local/bin/chrome-cdp-util

echo "=== Chrome configuration completed ==="

# Launch Chrome for the main VNC user
echo "Starting Chrome for ga user..."
su - ga -c "/home/ga/launch_chrome.sh about:blank" || true
sleep 3

echo "Chrome is ready! Users can:"
echo "  - Launch from desktop shortcut"
echo "  - Run 'google-chrome-stable' from terminal"
echo "  - Run '~/launch_chrome.sh' for CDP-enabled Chrome"
echo "  - Access CDP on port 9222 (forwarded to 1337)"
echo "  - Use 'chrome-cdp-util' for CDP queries"
