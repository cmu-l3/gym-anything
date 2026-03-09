#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Notification Permission Cleanup Task Setup ==="
echo "Task: Revoke notification permissions from unwanted websites"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python JSON manipulation tool if needed
pip3 install -q jsonschema 2>/dev/null || true

# Wait for environment to be ready
sleep 2

echo "Configuring Chrome with notification permissions..."

# Define Chrome profile paths to try
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Determine which profile to use
if [ -d "$CHROME_PROFILE" ]; then
    PROFILE_PATH="$CHROME_PROFILE"
elif [ -d "$ALT_PROFILE" ]; then
    PROFILE_PATH="$ALT_PROFILE"
else
    # Create the directory if it doesn't exist
    PROFILE_PATH="$CHROME_PROFILE"
    mkdir -p "$PROFILE_PATH"
    chown -R ga:ga "$(dirname $CHROME_PROFILE)"
fi

PREFS_FILE="$PROFILE_PATH/Preferences"

echo "Using Chrome profile: $PROFILE_PATH"

# Stop Chrome if it's running to safely modify Preferences
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Stopping Chrome to modify preferences..."
    pkill -f "google-chrome" || true
    sleep 2
    
    # Force kill if still running
    if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
        pkill -9 -f "google-chrome" || true
        sleep 1
    fi
fi

# Backup existing Preferences if present
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" "$PREFS_FILE.backup_$(date +%s)"
    echo "✓ Backed up existing Preferences"
fi

# Create or modify Preferences file with notification permissions
echo "Injecting notification permissions..."

# Use Python to safely manipulate JSON
python3 << 'PYTHON_SCRIPT'
import json
import os
import sys

prefs_file = os.environ.get('PREFS_FILE')

# Load existing preferences or create new structure
if os.path.exists(prefs_file):
    try:
        with open(prefs_file, 'r', encoding='utf-8') as f:
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

notifications = prefs['profile']['content_settings']['exceptions']['notifications']

# Add notification permissions for target domains
# Setting: 1 = ALLOW, 2 = BLOCK
# We'll set them to ALLOW initially so the agent needs to change them

# Target domains that should be revoked
target_domains = [
    "https://newsdaily.com:443,*",
    "https://celebritygossip.net:443,*",
    "https://dealsalert.shop:443,*"
]

# Control domain that should be preserved
preserve_domains = [
    "https://work-calendar.company.com:443,*"
]

# Get current timestamp (Chrome uses microseconds since Windows epoch)
# For simplicity, use a fixed recent timestamp
timestamp = "13360000000000000"

# Add ALLOW permissions for all domains initially
for domain in target_domains:
    notifications[domain] = {
        "last_modified": timestamp,
        "setting": 1  # ALLOW
    }
    print(f"Added ALLOW permission for: {domain}")

for domain in preserve_domains:
    notifications[domain] = {
        "last_modified": timestamp,
        "setting": 1  # ALLOW
    }
    print(f"Added ALLOW permission for: {domain} (should be preserved)")

# Save modified preferences
with open(prefs_file, 'w', encoding='utf-8') as f:
    json.dump(prefs, f, indent=2)

print(f"✓ Preferences saved to: {prefs_file}")
PYTHON_SCRIPT

chown ga:ga "$PREFS_FILE"
echo "✓ Notification permissions injected into Preferences"

# Start Chrome with the modified preferences
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://settings/content/notifications" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
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

# Navigate to notification settings page
echo "Navigating to notification settings..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/content/notifications'" || true
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
echo "Chrome should be displaying notification settings page"
echo "Injected permissions:"
echo "  - newsdaily.com (ALLOW - should be revoked)"
echo "  - celebritygossip.net (ALLOW - should be revoked)"
echo "  - dealsalert.shop (ALLOW - should be revoked)"
echo "  - work-calendar.company.com (ALLOW - should be preserved)"
echo ""
echo "Agent should:"
echo "  1. Navigate to Settings > Privacy and security > Site Settings > Notifications"
echo "  2. Find and revoke permissions for the three unwanted sites"
echo "  3. Preserve permission for work-calendar.company.com"