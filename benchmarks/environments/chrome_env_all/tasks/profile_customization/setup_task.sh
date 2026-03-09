#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Profile Customization Task Setup ==="
echo "Task: Customize Chrome profile name and avatar icon"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

echo "Setting up Chrome profile environment..."

# Ensure Chrome profile directories exist
CHROME_PROFILE_DIR="/home/ga/.config/google-chrome-cdp/Default"
CHROME_ALT_DIR="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE_DIR" "$CHROME_ALT_DIR"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp" "/home/ga/.config/google-chrome" 2>/dev/null || true

# Reset profile to default state to ensure consistent starting point
echo "Resetting profile to default state..."
PREFS_FILE="$CHROME_PROFILE_DIR/Preferences"
if [ -f "$PREFS_FILE" ]; then
    # Backup existing preferences
    cp "$PREFS_FILE" "$PREFS_FILE.backup.$(date +%s)" 2>/dev/null || true
    
    # Reset profile settings to defaults using Python
    python3 - <<'EOF'
import json
import sys

try:
    with open("/home/ga/.config/google-chrome-cdp/Default/Preferences", 'r') as f:
        prefs = json.load(f)
    
    # Reset profile to default values
    if 'profile' not in prefs:
        prefs['profile'] = {}
    
    prefs['profile']['name'] = 'Person 1'
    prefs['profile']['avatar_icon'] = 'chrome://theme/IDR_PROFILE_AVATAR_26'
    
    with open("/home/ga/.config/google-chrome-cdp/Default/Preferences", 'w') as f:
        json.dump(prefs, f, indent=2)
    
    print("✓ Profile reset to default state")
except Exception as e:
    print(f"Note: Could not reset profile (first run): {e}")
    sys.exit(0)
EOF
else
    echo "No existing preferences found (first run)"
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

# Navigate to a simple starting page
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

echo "=== Setup complete ==="
echo "Chrome is ready with default profile ('Person 1' with default avatar)"
echo ""
echo "Agent should now:"
echo "  1. Click the profile icon in Chrome toolbar (top-right)"
echo "  2. Click on profile name or gear icon to access profile settings"
echo "  3. OR navigate to chrome://settings/manageProfile directly"
echo "  4. Change profile name to something custom (e.g., 'Research Browser', 'Work Profile')"
echo "  5. Select a different avatar icon from the available options"
echo "  6. Click 'Done' or confirm to save changes"