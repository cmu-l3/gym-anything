#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Autofill Address Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if still in settings
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent appears to be in Settings"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are saved to disk
echo "Closing Chrome to save autofill preferences..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for autofill verification..."

# Try primary location (chrome-cdp profile)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_autofill.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Log autofill profile count
    PROFILE_COUNT=$(jq '.autofill.profiles | length // 0' /tmp/chrome_preferences_autofill.json 2>/dev/null || echo "0")
    echo "Autofill profiles found: $PROFILE_COUNT"
    
    # Log profile details for debugging
    if [ "$PROFILE_COUNT" -gt 0 ]; then
        echo "Profile preview:"
        jq '.autofill.profiles[] | {name: .name_full, city: .city, guid: .guid}' /tmp/chrome_preferences_autofill.json 2>/dev/null || true
    fi
else
    echo "⚠ Warning: Preferences not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location (standard chrome profile)
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_autofill.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
        PROFILE_COUNT=$(jq '.autofill.profiles | length // 0' /tmp/chrome_preferences_autofill.json 2>/dev/null || echo "0")
        echo "Autofill profiles found: $PROFILE_COUNT"
    else
        echo "✗ Could not find Preferences file in any known location"
        # Create empty file to prevent verifier errors
        echo '{"autofill":{"profiles":[]}}' > /tmp/chrome_preferences_autofill.json
    fi
fi

# Also copy to standard temp location for verifier
cp /tmp/chrome_preferences_autofill.json /tmp/chrome_preferences.json 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files ready at /tmp/chrome_preferences_autofill.json"