#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Block Notification Spam Task Export ==="

# Focus Chrome window one last time to ensure settings are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP for additional verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json 2>/dev/null || echo "")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save notification settings..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_export.json"
    echo "  from: $CHROME_PROFILE/Preferences"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location"
        echo "  from: $ALT_PROFILE/Preferences"
    else
        echo "✗ Could not find Preferences file in any known location"
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Show notification permissions for debugging
echo ""
echo "Notification permissions in Preferences:"
if [ -f /tmp/chrome_preferences_export.json ]; then
    python3 << 'EOF' 2>/dev/null || echo "Could not parse notification permissions"
import json
try:
    with open('/tmp/chrome_preferences_export.json', 'r') as f:
        prefs = json.load(f)
    notifications = prefs.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('notifications', {})
    if notifications:
        print(f"  Found {len(notifications)} notification permission(s)")
        for domain, perm in notifications.items():
            setting = perm.get('setting', 0)
            setting_name = {0: 'ASK', 1: 'ALLOW', 2: 'BLOCK'}.get(setting, f'UNKNOWN({setting})')
            print(f"    {domain}: {setting_name}")
    else:
        print("  No notification permissions found")
except Exception as e:
    print(f"  Error parsing: {e}")
EOF
fi

echo ""
echo "✅ Export complete"