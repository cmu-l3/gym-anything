#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network Request Blocking Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/network_blocking_verification"
mkdir -p "$VERIFY_DIR"

# Try to capture network activity via CDP before closing Chrome
echo "Attempting to capture network state via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ Captured CDP tab information"
    
    # Get active tab for additional context
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Gracefully close Chrome to ensure DevTools preferences are persisted to disk
echo "Closing Chrome to save DevTools preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
    echo "✓ Preferences exported to $VERIFY_DIR/chrome_preferences.json"
    
    # Also copy to /tmp for easier access
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    
    # Extract just the DevTools preferences section for easier debugging
    if command -v jq &> /dev/null; then
        jq '.devtools // {}' "$VERIFY_DIR/chrome_preferences.json" > "$VERIFY_DIR/devtools_prefs.json" 2>/dev/null || true
        echo "✓ DevTools preferences extracted"
    fi
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any known location"
        echo "null" > "$VERIFY_DIR/chrome_preferences.json"
    fi
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"