#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome HTTPS-Only Mode Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any pending changes are applied
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent was on settings page
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was on settings page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences..."
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
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Show file size for debugging
    ls -lh "$CHROME_PROFILE/Preferences"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
        ls -lh "$ALT_PROFILE/Preferences"
    else
        echo "✗ Could not find Preferences file in any known location"
        # Create empty JSON to prevent verifier errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Quick check of HTTPS-Only mode setting for debugging
if [ -f /tmp/chrome_preferences_export.json ]; then
    echo "Quick check of HTTPS-Only mode setting..."
    python3 -c "
import json
try:
    with open('/tmp/chrome_preferences_export.json', 'r') as f:
        prefs = json.load(f)
    
    # Check multiple possible setting locations
    https_enabled = None
    setting_location = None
    
    if prefs.get('generated', {}).get('https_only_mode_enabled') is True:
        https_enabled = True
        setting_location = 'generated.https_only_mode_enabled'
    elif prefs.get('https_only_mode_enabled') is True:
        https_enabled = True
        setting_location = 'https_only_mode_enabled'
    elif prefs.get('generated', {}).get('https_first_mode_enabled') is True:
        https_enabled = True
        setting_location = 'generated.https_first_mode_enabled'
    
    if https_enabled:
        print(f'✓ HTTPS-Only mode appears to be enabled at: {setting_location}')
    else:
        print('⚠ HTTPS-Only mode does not appear to be enabled')
        print('   (This is just a quick check; full verification will be done by verifier.py)')
except Exception as e:
    print(f'Could not parse preferences for quick check: {e}')
" || true
fi

echo "✅ Export complete"
echo "Verification files available at /tmp/ for verifier access"