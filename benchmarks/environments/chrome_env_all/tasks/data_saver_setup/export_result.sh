#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Data Saver Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Final active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if user was in settings
    if echo "$ACTIVE_URL" | grep -q "chrome://settings"; then
        echo "✓ User was in Chrome settings page"
    else
        echo "⚠ User navigated away from settings (at: $ACTIVE_URL)"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || pkill -f "chrome.*remote-debugging-port" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "✓ Chrome closed successfully"

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."

# Try primary location (chrome-cdp profile)
CHROME_PROFILE_PRIMARY="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE_PRIMARY/Preferences" ]; then
    cp "$CHROME_PROFILE_PRIMARY/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported from primary location: $CHROME_PROFILE_PRIMARY"
    ls -lh "$CHROME_PROFILE_PRIMARY/Preferences"
else
    echo "⚠ Preferences not found at primary location: $CHROME_PROFILE_PRIMARY"
    
    # Try alternative location (standard chrome profile)
    CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
        cp "$CHROME_PROFILE_ALT/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $CHROME_PROFILE_ALT"
        ls -lh "$CHROME_PROFILE_ALT/Preferences"
    else
        echo "✗ ERROR: Could not find Preferences file at any location"
        echo "Searched locations:"
        echo "  - $CHROME_PROFILE_PRIMARY/Preferences"
        echo "  - $CHROME_PROFILE_ALT/Preferences"
        
        # List directory contents for debugging
        echo "Contents of chrome-cdp Default directory:"
        ls -la "$CHROME_PROFILE_PRIMARY/" 2>/dev/null || echo "  Directory not found"
        
        echo "Contents of chrome Default directory:"
        ls -la "$CHROME_PROFILE_ALT/" 2>/dev/null || echo "  Directory not found"
        
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Also copy to standard location that verifier might check
cp /tmp/chrome_preferences_export.json /tmp/Preferences 2>/dev/null || true

# Validate exported Preferences is valid JSON
echo "Validating exported Preferences file..."
if command -v python3 &> /dev/null; then
    if python3 -c "import json; json.load(open('/tmp/chrome_preferences_export.json'))" 2>/dev/null; then
        echo "✓ Preferences file is valid JSON"
        # Get file size for debugging
        PREFS_SIZE=$(stat -f%z /tmp/chrome_preferences_export.json 2>/dev/null || stat -c%s /tmp/chrome_preferences_export.json 2>/dev/null || echo "unknown")
        echo "  File size: $PREFS_SIZE bytes"
    else
        echo "✗ WARNING: Preferences file is not valid JSON!"
    fi
fi

echo "✅ Export complete"
echo "Verification files saved to /tmp/ for verifier access"