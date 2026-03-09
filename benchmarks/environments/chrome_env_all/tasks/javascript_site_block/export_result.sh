#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome JavaScript Blocking Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure changes are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if we're still on settings page
    if echo "$ACTIVE_URL" | grep -q "chrome://settings"; then
        echo "✓ Agent is on Chrome settings page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save content settings..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    ls -lh "$CHROME_PROFILE/Preferences"
else
    echo "⚠ Primary profile not found, trying alternative location..."
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from: $ALT_PROFILE/Preferences"
        ls -lh "$ALT_PROFILE/Preferences"
    else
        echo "✗ Error: Preferences file not found in any known location"
        touch /tmp/chrome_preferences.json  # Create empty file to prevent verifier errors
    fi
fi

# Quick check if JavaScript exceptions exist (for debugging)
if [ -f /tmp/chrome_preferences.json ] && [ -s /tmp/chrome_preferences.json ]; then
    if command -v jq &> /dev/null; then
        JS_EXCEPTIONS=$(jq '.profile.content_settings.exceptions.javascript // {}' /tmp/chrome_preferences.json 2>/dev/null || echo "{}")
        if [ "$JS_EXCEPTIONS" != "{}" ]; then
            echo "✓ JavaScript exceptions found in Preferences"
            echo "$JS_EXCEPTIONS" | jq 'keys' 2>/dev/null || true
        else
            echo "⚠ No JavaScript exceptions found in Preferences"
        fi
    fi
fi

echo "✅ Export complete"
echo "Verification files ready in /tmp/"