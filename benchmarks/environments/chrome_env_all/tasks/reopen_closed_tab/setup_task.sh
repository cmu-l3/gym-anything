#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Reopen Closed Tab Task Setup: reopen_closed_tab@1 ==="
echo "Task: Recover accidentally closed tab using Ctrl+Shift+T"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to starting URL
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Verify Chrome is ready via CDP
if ! curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "⚠ Warning: Chrome CDP not responding, waiting..."
    sleep 3
fi

# Now open additional tabs to create a realistic browsing session
echo "Opening multiple tabs to simulate browsing session..."

# Define the target URL that will be "accidentally" closed
TARGET_URL="https://en.wikipedia.org/wiki/Computer_science"

# Open tabs using CDP via Python
python3 << 'PYTHON_SETUP'
import requests
import json
import time
import sys

CDP_PORT = 9222
TARGET_URL = "https://en.wikipedia.org/wiki/Computer_science"

def get_tabs():
    """Get all open tabs"""
    try:
        response = requests.get(f'http://localhost:{CDP_PORT}/json', timeout=5)
        return response.json()
    except Exception as e:
        print(f"Error getting tabs: {e}", file=sys.stderr)
        return []

def create_tab(url):
    """Create a new tab with URL via CDP"""
    try:
        response = requests.get(f'http://localhost:{CDP_PORT}/json/new?{url}', timeout=5)
        time.sleep(0.5)
        return response.json()
    except Exception as e:
        print(f"Error creating tab: {e}", file=sys.stderr)
        return None

def close_tab(tab_id):
    """Close a specific tab"""
    try:
        requests.get(f'http://localhost:{CDP_PORT}/json/close/{tab_id}', timeout=5)
        return True
    except Exception as e:
        print(f"Error closing tab: {e}", file=sys.stderr)
        return False

# URLs to open (creating a realistic browsing session)
urls_to_open = [
    "https://github.com",
    TARGET_URL,  # This is the one we'll "accidentally" close
    "https://stackoverflow.com"
]

print("Opening tabs for browsing session...")
for url in urls_to_open:
    print(f"  Opening: {url}")
    create_tab(url)
    time.sleep(1.5)

# Give pages time to load
print("Waiting for pages to load...")
time.sleep(3)

# Find and close the target tab to simulate accidental closure
print(f"Simulating accidental closure of: {TARGET_URL}")
tabs = get_tabs()
target_tab_id = None

for tab in tabs:
    tab_url = tab.get('url', '')
    tab_id = tab.get('id', '')
    if TARGET_URL.lower() in tab_url.lower():
        target_tab_id = tab_id
        print(f"  Found target tab: {tab_id}")
        break

if target_tab_id:
    if close_tab(target_tab_id):
        print(f"✓ Closed target tab: {TARGET_URL}")
        
        # Save target URL for verifier
        with open('/tmp/closed_tab_url.txt', 'w') as f:
            f.write(TARGET_URL)
        
        # Record the timestamp
        with open('/tmp/tab_close_time.txt', 'w') as f:
            f.write(str(time.time()))
        
        print(f"✓ Saved target URL to /tmp/closed_tab_url.txt")
    else:
        print("✗ Failed to close target tab", file=sys.stderr)
        sys.exit(1)
else:
    print(f"✗ Could not find target tab with URL: {TARGET_URL}", file=sys.stderr)
    # Save URL anyway for verifier
    with open('/tmp/closed_tab_url.txt', 'w') as f:
        f.write(TARGET_URL)
    sys.exit(1)

PYTHON_SETUP

SETUP_EXIT_CODE=$?

if [ $SETUP_EXIT_CODE -ne 0 ]; then
    echo "⚠ Warning: Tab setup script had issues (exit code: $SETUP_EXIT_CODE)"
    # Still continue - verifier will handle missing state
fi

# Verify target URL was closed
if [ -f /tmp/closed_tab_url.txt ]; then
    CLOSED_URL=$(cat /tmp/closed_tab_url.txt)
    echo "✓ Target URL recorded: $CLOSED_URL"
else
    echo "⚠ Warning: closed_tab_url.txt not found"
fi

# Focus Chrome window again
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Get current tab count for logging
CURRENT_TABS=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
echo "✓ Current open tabs: $CURRENT_TABS"

echo "=== Setup complete ==="
echo "Chrome has multiple tabs open, and one tab ($TARGET_URL) was just 'accidentally' closed"
echo "Agent task: Reopen the closed tab using Ctrl+Shift+T or right-click menu"