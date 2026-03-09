#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Memory Saver Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
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
    
    # Check if agent was on settings page
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was on Chrome settings page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/memory_saver_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/memory_saver_screenshot.png"
fi

# Give Chrome a moment to finish any pending operations
sleep 1

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed (force kill if needed)
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force closing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    ls -lh "$CHROME_PROFILE/Preferences"
else
    echo "⚠ Preferences not found at primary location: $CHROME_PROFILE"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
        ls -lh "$ALT_PROFILE/Preferences"
    else
        echo "✗ Error: Could not find Preferences file at any known location"
        echo "Searched locations:"
        echo "  - $CHROME_PROFILE/Preferences"
        echo "  - $ALT_PROFILE/Preferences"
        
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences.json
    fi
fi

# Quick check if Memory Saver configuration exists in exported file
if [ -f /tmp/chrome_preferences.json ]; then
    echo ""
    echo "Quick Memory Saver state check:"
    MEMORY_SAVER_STATE=$(jq -r '.performance_tuning.high_efficiency_mode.state // "not_found"' /tmp/chrome_preferences.json 2>/dev/null || echo "parse_error")
    echo "  performance_tuning.high_efficiency_mode.state = $MEMORY_SAVER_STATE"
    
    # Try alternative paths
    if [ "$MEMORY_SAVER_STATE" == "not_found" ]; then
        ALT_STATE=$(jq -r '.performance_tuning.high_efficiency_mode.enabled // "not_found"' /tmp/chrome_preferences.json 2>/dev/null || echo "parse_error")
        echo "  performance_tuning.high_efficiency_mode.enabled = $ALT_STATE"
    fi
fi

echo ""
echo "✅ Export complete"
echo "Verification files available:"
echo "  - /tmp/chrome_preferences.json (Preferences file)"
echo "  - /tmp/final_url.txt (Last active URL)"
echo "  - /tmp/memory_saver_screenshot.png (Final screenshot)"