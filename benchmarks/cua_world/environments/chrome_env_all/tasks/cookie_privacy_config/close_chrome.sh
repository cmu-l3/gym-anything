#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Cookie Privacy Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are applied
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification that agent was in settings
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent was in settings
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was in Chrome settings"
    else
        echo "⚠ Warning: Agent may not have accessed Chrome settings (URL: $ACTIVE_URL)"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Give Chrome a moment to persist any pending writes
echo "Allowing Chrome to persist settings..."
sleep 2

# Gracefully close Chrome to ensure Preferences are properly saved
echo "Closing Chrome to save cookie preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_after.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_after.json"
    
    # Extract and log the cookie settings for debugging
    COOKIE_MODE=$(jq -r '.profile.cookie_controls_mode // "not_set"' /tmp/chrome_preferences_after.json 2>/dev/null || echo "parse_error")
    BLOCK_THIRD_PARTY=$(jq -r '.profile.block_third_party_cookies // false' /tmp/chrome_preferences_after.json 2>/dev/null || echo "false")
    
    echo "Cookie settings after task:"
    echo "  cookie_controls_mode: $COOKIE_MODE"
    echo "  block_third_party_cookies: $BLOCK_THIRD_PARTY"
    
    # Compare with backup if available
    if [ -f "$CHROME_PROFILE/Preferences.backup_before_task" ]; then
        OLD_COOKIE_MODE=$(jq -r '.profile.cookie_controls_mode // 0' "$CHROME_PROFILE/Preferences.backup_before_task" 2>/dev/null || echo "0")
        if [ "$COOKIE_MODE" != "$OLD_COOKIE_MODE" ]; then
            echo "✓ Cookie settings were modified (was: $OLD_COOKIE_MODE, now: $COOKIE_MODE)"
        else
            echo "⚠ Cookie settings appear unchanged"
        fi
    fi
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_after.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any known location"
        touch /tmp/chrome_preferences_after.json  # Create empty file to prevent verifier errors
    fi
fi

# Also copy to standard verification location
cp /tmp/chrome_preferences_after.json /tmp/chrome_preferences.json 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files ready for analysis"