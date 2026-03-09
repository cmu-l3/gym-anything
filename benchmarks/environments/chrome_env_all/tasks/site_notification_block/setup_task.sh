#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Notification Blocking Task Setup ==="
echo "Task: Block notifications from nytimes.com via Chrome settings"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE_DIR="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE_DIR"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp" || true

# Back up original Preferences if exists (for verification comparison)
if [ -f "$CHROME_PROFILE_DIR/Preferences" ]; then
    cp "$CHROME_PROFILE_DIR/Preferences" "$CHROME_PROFILE_DIR/Preferences.backup" || true
    echo "✓ Backed up existing Preferences"
fi

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

# Navigate to the starting URL (Google homepage as neutral starting point)
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

# Clear any pre-existing notification blocks for target site (ensure clean slate)
echo "Preparing clean slate for task..."
if [ -f "$CHROME_PROFILE_DIR/Preferences" ]; then
    # Remove any pre-existing nytimes.com notification exceptions
    # This ensures the agent must actually perform the task
    python3 << 'PYPYTHON'
import json
import sys

prefs_path = "/home/ga/.config/google-chrome-cdp/Default/Preferences"
try:
    with open(prefs_path, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
    
    # Navigate to notification exceptions
    notifications = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('notifications', {})
    
    # Remove any nytimes.com entries
    keys_to_remove = []
    for pattern in notifications.keys():
        if 'nytimes.com' in pattern.lower():
            keys_to_remove.append(pattern)
    
    for key in keys_to_remove:
        del notifications[pattern]
        print(f"Removed pre-existing entry: {key}", file=sys.stderr)
    
    # Save if modified
    if keys_to_remove:
        with open(prefs_path, 'w', encoding='utf-8') as f:
            json.dump(prefs, f, indent=2)
        print("✓ Cleaned pre-existing notification settings", file=sys.stderr)
    
except Exception as e:
    print(f"Warning: Could not clean preferences: {e}", file=sys.stderr)
PYPYTHON
fi

# Take initial screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot saved"
fi

echo "=== Setup complete ==="
echo "Chrome is ready on Google homepage"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings (or use menu: Settings)"
echo "  2. Click 'Privacy and security' in left sidebar"
echo "  3. Click 'Site Settings'"
echo "  4. Click 'Notifications'"
echo "  5. Click 'Add' button next to 'Not allowed to send notifications'"
echo "  6. Enter '[*.]nytimes.com' or 'nytimes.com'"
echo "  7. Click 'Add' to confirm"
echo ""
echo "Target site: nytimes.com"