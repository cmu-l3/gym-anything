#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Resource Preloading Configuration Task Setup ==="
echo "Task: Configure Extended preloading for maximum performance"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
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

# Navigate to the starting URL (Google homepage)
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

# Reset preloading to default state (Standard or No preloading)
# This ensures the agent has to actually change the setting
echo "Resetting preloading preference to default state..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

# Try primary profile location
if [ ! -d "$CHROME_PROFILE" ]; then
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    # Backup original preferences
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup" || true
    
    # Use Python to modify the JSON safely
    python3 << PYTHON_SCRIPT
import json
import sys
import os

prefs_path = "$CHROME_PROFILE/Preferences"
try:
    with open(prefs_path, 'r') as f:
        prefs = json.load(f)
    
    # Set to Standard preloading (value 1 or 2) as starting state
    # This ensures agent must change it to Extended
    if 'net' not in prefs:
        prefs['net'] = {}
    
    # For newer Chrome versions, use preload_pages
    # Set to 1 (Standard) so agent must change to 2 (Extended)
    prefs['net']['preload_pages'] = 1
    
    # For older Chrome versions, use network_prediction_options  
    # Set to 2 (Standard) so agent must change to 0 (Always/Extended)
    prefs['net']['network_prediction_options'] = 2
    
    with open(prefs_path, 'w') as f:
        json.dump(prefs, f, indent=2)
    
    print("✓ Reset network prediction to Standard/Default mode")
except Exception as e:
    print(f"⚠ Could not reset preferences: {e}", file=sys.stderr)
PYTHON_SCRIPT
    
    # Ensure proper ownership
    chown ga:ga "$CHROME_PROFILE/Preferences" || true
else
    echo "⚠ Warning: Preferences file not found, starting with defaults"
fi

echo "=== Setup complete ==="
echo "Chrome is ready. Agent should:"
echo "  1. Navigate to chrome://settings or chrome://settings/cookies"
echo "  2. Find 'Preload pages' setting in Privacy and security"
echo "  3. Select 'Extended preloading' option for maximum performance"