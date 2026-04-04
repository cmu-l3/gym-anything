#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site Permission Management Task Setup ==="
echo "Task: Revoke notification permission for spam-sending news site"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is NOT running initially so we can modify preferences
echo "Ensuring Chrome is stopped before modifying preferences..."
pkill -f "chrome.*remote-debugging-port" || true
pkill -9 chrome || true
sleep 2

# Determine Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    echo "Chrome CDP profile not found, trying standard location..."
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

# Create profile directory if it doesn't exist
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "$(dirname "$CHROME_PROFILE")"

PREFS_FILE="$CHROME_PROFILE/Preferences"

echo "Setting up notification permissions in Chrome preferences..."

# Use Python to surgically modify the Preferences file
python3 << 'PYTHON_SCRIPT'
import json
import os
import time

prefs_file = os.environ.get('PREFS_FILE', '/home/ga/.config/google-chrome-cdp/Default/Preferences')

# Load existing preferences or create new structure
if os.path.exists(prefs_file):
    print(f"Loading existing preferences from: {prefs_file}")
    with open(prefs_file, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
else:
    print(f"Creating new preferences file at: {prefs_file}")
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

# Current timestamp (Chrome uses microseconds since Windows epoch)
# For simplicity, use a large number representing recent time
timestamp = "13360000000000000"

# Add the problematic news site with ALLOW permission (value = 1)
# This is the site the agent needs to revoke
problematic_site_pattern = "https://news-daily-times.example:443,*"
notifications[problematic_site_pattern] = {
    "last_modified": timestamp,
    "setting": 1  # ALLOW = 1
}

# Add legitimate sites that should NOT be touched
# These represent work/important sites the user wants to keep
notifications["https://work-slack.example:443,*"] = {
    "last_modified": "13359999000000000",
    "setting": 1  # ALLOW
}

notifications["https://mail.google.com:443,*"] = {
    "last_modified": "13359998000000000",
    "setting": 1  # ALLOW
}

notifications["https://calendar.google.com:443,*"] = {
    "last_modified": "13359997000000000",
    "setting": 1  # ALLOW
}

# Add one blocked site to show the user has used this feature before
notifications["https://spam-ads.example:443,*"] = {
    "last_modified": "13359996000000000",
    "setting": 2  # BLOCK = 2
}

# Write back to file
os.makedirs(os.path.dirname(prefs_file), exist_ok=True)
with open(prefs_file, 'w', encoding='utf-8') as f:
    json.dump(prefs, f, indent=2)

print("✓ Notification permissions configured:")
print(f"  - news-daily-times.example: ALLOWED (to be revoked)")
print(f"  - work-slack.example: ALLOWED (keep)")
print(f"  - mail.google.com: ALLOWED (keep)")
print(f"  - calendar.google.com: ALLOWED (keep)")
print(f"  - spam-ads.example: BLOCKED (already blocked)")

PYTHON_SCRIPT

# Save the "before" state for verification comparison
echo "Saving 'before' state of preferences..."
cp "$PREFS_FILE" "/tmp/preferences_before_task.json"
chown ga:ga "/tmp/preferences_before_task.json"
echo "✓ Before-state saved to /tmp/preferences_before_task.json"

# Now start Chrome with the modified preferences
echo "Starting Chrome with configured permissions..."
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Launching Chrome..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 6
else
    echo "Chrome already running"
fi

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

# Navigate to a neutral starting page (Google)
echo "Navigating to starting page..."
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

echo ""
echo "=== Setup complete ==="
echo ""
echo "📋 Scenario:"
echo "  User granted notification permission to 'news-daily-times.example' weeks ago"
echo "  expecting breaking news alerts. Instead, they receive 10+ clickbait spam"
echo "  notifications daily. User wants to revoke this specific site's permission"
echo "  WITHOUT affecting important sites (Slack, Gmail, Calendar)."
echo ""
echo "🎯 Agent Task:"
echo "  1. Navigate to Chrome Settings (chrome://settings or via menu)"
echo "  2. Go to Privacy and security → Site Settings → Notifications"
echo "  3. Find 'news-daily-times.example' in the 'Allowed to send notifications' list"
echo "  4. Revoke its permission (remove or block it)"
echo "  5. Ensure other sites' permissions remain unchanged"
echo ""
echo "✓ Current state: 4 sites allowed, 1 site blocked"
echo "✓ Target: Revoke permission for news-daily-times.example only"