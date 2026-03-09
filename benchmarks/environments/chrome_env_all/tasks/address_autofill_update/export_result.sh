#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Address Autofill Update Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if user was in settings
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was in Chrome settings"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure autofill data is persisted to disk
echo "Closing Chrome to save autofill preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Determine Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -f "$CHROME_PROFILE/Preferences" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

echo "Using Chrome profile: $CHROME_PROFILE"

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for autofill verification..."
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_autofill.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_autofill.json"
    
    # Show summary of addresses found
    echo "Current addresses in autofill:"
    python3 << 'PYTHON_SCRIPT' || true
import json
try:
    with open('/tmp/chrome_preferences_autofill.json', 'r') as f:
        prefs = json.load(f)
    profiles = prefs.get('autofill', {}).get('profile_address_data_manager', {}).get('profiles', [])
    print(f"  Total addresses: {len(profiles)}")
    for i, profile in enumerate(profiles, 1):
        street = profile.get('street-address', 'N/A')
        city = profile.get('city', 'N/A')
        state = profile.get('state', 'N/A')
        print(f"  {i}. {street}, {city}, {state}")
except Exception as e:
    print(f"  Could not parse addresses: {e}")
PYTHON_SCRIPT
    
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Create empty file to prevent verification errors
    echo '{}' > /tmp/chrome_preferences_autofill.json
fi

# Also copy to standard location for verification utilities
cp /tmp/chrome_preferences_autofill.json /tmp/chrome_preferences.json 2>/dev/null || true

echo "✅ Export complete"