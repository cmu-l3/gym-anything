#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Block Notification Spam Task Setup ==="
echo "Task: Block notification permissions for spam domain"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running and close it to modify preferences
CHROME_RUNNING=false
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome is already running, closing it to modify preferences..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Wait to ensure Chrome is fully closed
sleep 1

# Modify Chrome Preferences to add notification permission for spam domain
echo "Adding notification permission for spam domain..."

# Determine Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    mkdir -p "$CHROME_PROFILE"
fi

PREFS_FILE="$CHROME_PROFILE/Preferences"

# Create or modify Preferences file to add spam notification permission
python3 << 'EOF'
import json
import os
import time

# Determine profile path
chrome_profile = "/home/ga/.config/google-chrome-cdp/Default"
if not os.path.isdir(chrome_profile):
    chrome_profile = "/home/ga/.config/google-chrome/Default"
    os.makedirs(chrome_profile, exist_ok=True)

prefs_path = os.path.join(chrome_profile, "Preferences")

# Load existing preferences or create new
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
    except:
        prefs = {}
else:
    prefs = {}

# Ensure nested structure exists
if 'profile' not in prefs:
    prefs['profile'] = {}
if 'content_settings' not in prefs['profile']:
    prefs['profile']['content_settings'] = {}
if 'exceptions' not in prefs['profile']['content_settings']:
    prefs['profile']['content_settings']['exceptions'] = {}
if 'notifications' not in prefs['profile']['content_settings']['exceptions']:
    prefs['profile']['content_settings']['exceptions']['notifications'] = {}

# Add spam domain with ALLOW permission (value 1)
# Chrome uses timestamp in microseconds since Windows epoch (1601-01-01)
timestamp = str(int((time.time() + 11644473600) * 1000000))

spam_domain = "https://news-spam-example.com:443,*"
prefs['profile']['content_settings']['exceptions']['notifications'][spam_domain] = {
    'last_modified': timestamp,
    'setting': 1  # 1 = ALLOW
}

# Write back to file
with open(prefs_path, 'w') as f:
    json.dump(prefs, f, indent=2)

print(f"✓ Added ALLOW notification permission for news-spam-example.com")
print(f"  Preferences file: {prefs_path}")
EOF

# Change ownership to ga user
chown -R ga:ga "$CHROME_PROFILE" || true

echo "Preferences modified, now starting Chrome..."
sleep 1

# Start Chrome
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Starting Chrome..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is running"
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

echo "=== Setup complete ==="
echo "Chrome is ready with spam notification permission set."
echo "Agent should:"
echo "  1. Navigate to chrome://settings or use Settings menu"
echo "  2. Go to Privacy and security > Site Settings > Notifications"
echo "  3. Find news-spam-example.com in allowed list"
echo "  4. Change permission to Block or remove it"