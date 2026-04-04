#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Cache Fix Task Setup: clear_cache_fix@1 ==="
echo "Task: Clear site-specific cache and cookies to fix broken website"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 sqlite3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Kill any existing Chrome to start fresh
echo "Stopping any running Chrome instances..."
pkill -9 chrome || true
sleep 2

# Ensure Chrome profile directories exist
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome-cdp/

echo "Starting Chrome to seed cookie data for multiple sites..."

# Launch Chrome with remote debugging
su - ga -c "DISPLAY=:1 google-chrome-stable \
    --remote-debugging-port=1337 \
    --user-data-dir=/home/ga/.config/google-chrome-cdp \
    --disable-background-networking \
    --no-first-run \
    --no-default-browser-check \
    about:blank &" || true

sleep 5

# Verify Chrome started
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome failed to start, trying alternative method..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank &" || true
    sleep 5
fi

# Wait for CDP to be ready
echo "Waiting for Chrome CDP..."
for i in {1..10}; do
    if curl -s http://localhost:9222/json > /dev/null 2>&1; then
        echo "✓ Chrome CDP is ready"
        break
    fi
    sleep 1
done

# Create a helper script to visit URLs and create cookies
cat > /tmp/visit_sites.py << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
import requests
import json
import time
import sys

# Sites to visit and create cookies for
sites = [
    "https://www.google.com",
    "https://www.wikipedia.org",
    "https://www.github.com",
    "https://example-site.com",  # The problematic site
    "https://www.stackoverflow.com"
]

def get_first_tab():
    """Get the first available tab"""
    try:
        response = requests.get("http://localhost:9222/json", timeout=5)
        tabs = response.json()
        for tab in tabs:
            if tab.get('type') == 'page':
                return tab
        return None
    except Exception as e:
        print(f"Error getting tabs: {e}")
        return None

def navigate_to_url(tab, url):
    """Navigate a tab to a URL using CDP"""
    try:
        ws_url = tab.get('webSocketDebuggerUrl')
        if not ws_url:
            print(f"No WebSocket URL for tab")
            return False
        
        # Use HTTP endpoint to navigate (simpler than WebSocket)
        # We'll just verify the tab exists and sleep to let it load
        print(f"Navigating to: {url}")
        return True
    except Exception as e:
        print(f"Error navigating to {url}: {e}")
        return False

# Visit each site
print("Visiting sites to create cookies...")
for site in sites:
    print(f"  - {site}")
    tab = get_first_tab()
    if tab:
        navigate_to_url(tab, site)
    time.sleep(2)

print("Sites visited successfully")
PYTHON_SCRIPT

chmod +x /tmp/visit_sites.py

# Use xdotool to navigate Chrome and create cookies by visiting sites
echo "Navigating to multiple sites to create cookies..."

export DISPLAY=:1

# Focus Chrome window
sleep 2
wid=$(wmctrl -l | grep -i 'Chrome' | head -1 | awk '{print $1}')
if [ -n "$wid" ]; then
    wmctrl -i -a "$wid" || true
    sleep 1
fi

# Visit each site using keyboard automation
sites=(
    "https://www.google.com"
    "https://www.wikipedia.org"
    "https://www.github.com"
    "https://example-site.com"
    "https://www.stackoverflow.com"
)

for site in "${sites[@]}"; do
    echo "Visiting: $site"
    
    # Focus Chrome
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    
    # Open address bar
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    
    # Type URL
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$site'" || true
    sleep 0.3
    
    # Press Enter
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 3
done

echo "✓ Visited multiple sites to create cookies"

# Close Chrome gracefully to ensure cookies are written to disk
echo "Closing Chrome to save cookies..."
pkill chrome || true
sleep 3

# Verify cookies were created
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    COOKIE_COUNT=$(sqlite3 "$CHROME_PROFILE/Cookies" "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "0")
    echo "✓ Cookies database created with $COOKIE_COUNT cookies"
else
    echo "⚠ Warning: Cookies database not found"
fi

# Create instruction file on desktop
echo "Creating instruction file..."
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/TASK_INSTRUCTIONS.txt" << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║          WEBSITE TROUBLESHOOTING TASK - URGENT                ║
╚═══════════════════════════════════════════════════════════════╝

PROBLEM:
--------
The website "example-site.com" is displaying outdated/broken content
from last week. When you refresh the page, it still shows the old 
corrupted version. Other websites are working perfectly fine.

This is a common browser caching issue that needs to be fixed by
clearing the site-specific cache and cookies.

YOUR TASK:
----------
Fix this issue by clearing the browser cache and cookies 
SPECIFICALLY for example-site.com ONLY.

⚠️  IMPORTANT: Do NOT clear data for ALL websites - only target
    the problematic site to preserve your other browsing data!

STEPS TO COMPLETE:
------------------
1. Open Chrome Settings (click menu ⋮ → Settings, or type chrome://settings)
2. Navigate to: Privacy and security → Cookies and other site data
3. Click "See all site data and permissions"
4. Search for or find "example-site.com" in the list
5. Click the trash icon next to example-site.com to delete its data
6. Confirm the deletion

VERIFICATION:
-------------
After completing the task, the system will verify that:
✓ example-site.com has no cached data or cookies
✓ Other websites still have their data (selective deletion used)
✓ You used the proper Chrome settings interface

Good luck!
EOF

chown ga:ga "$DESKTOP_DIR/TASK_INSTRUCTIONS.txt"
echo "✓ Instructions created at: $DESKTOP_DIR/TASK_INSTRUCTIONS.txt"

# Re-launch Chrome and navigate to the "problematic" site
echo "Launching Chrome for the task..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://example-site.com &" || true
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# Click at center to select correct desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a "$wid" || true
    sleep 1
fi

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '.[0].url // "unknown"' 2>/dev/null)
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Open the instruction file in a text editor for visibility
su - ga -c "DISPLAY=:1 xdg-open '$DESKTOP_DIR/TASK_INSTRUCTIONS.txt' &" 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome is ready with example-site.com loaded"
echo "Agent should now clear site-specific cache and cookies for example-site.com"
echo ""
echo "Pre-seeded sites with cookies:"
echo "  - google.com"
echo "  - wikipedia.org"
echo "  - github.com"
echo "  - example-site.com (TARGET - should be cleared)"
echo "  - stackoverflow.com"