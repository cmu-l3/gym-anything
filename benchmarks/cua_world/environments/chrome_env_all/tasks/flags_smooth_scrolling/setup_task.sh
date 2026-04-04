#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Experimental Flags Configuration Task Setup ==="
echo "Task: Navigate to chrome://flags and enable smooth scrolling"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

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

# Navigate to starting URL (Google as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Reset any existing flags to ensure clean starting state
echo "Resetting flags configuration to default state..."
LOCAL_STATE_PATH="/home/ga/.config/google-chrome-cdp/Local State"
if [ -f "$LOCAL_STATE_PATH" ]; then
    # Backup current Local State
    cp "$LOCAL_STATE_PATH" "$LOCAL_STATE_PATH.backup" || true
    
    # Remove any existing enabled_labs_experiments to start fresh
    python3 -c "
import json
try:
    with open('$LOCAL_STATE_PATH', 'r') as f:
        state = json.load(f)
    
    # Clear enabled experiments if they exist
    if 'browser' in state and 'enabled_labs_experiments' in state['browser']:
        state['browser']['enabled_labs_experiments'] = []
        
    with open('$LOCAL_STATE_PATH', 'w') as f:
        json.dump(state, f, indent=2)
    
    print('Cleared existing flags configuration')
except Exception as e:
    print(f'Note: Could not reset flags (this is OK): {e}')
" || true
fi

echo "=== Setup complete ==="
echo "Chrome is ready at: https://www.google.com"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://flags (type in address bar)"
echo "  2. Search for 'smooth scrolling' in the search box"
echo "  3. Find the 'Smooth Scrolling' flag dropdown"
echo "  4. Change dropdown from 'Default' to 'Enabled'"
echo "  5. Click the 'Relaunch' button that appears at the bottom"