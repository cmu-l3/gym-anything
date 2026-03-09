#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Flags Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
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
    
    # Check if user is on chrome://flags page
    if [[ "$ACTIVE_URL" == *"chrome://flags"* ]]; then
        echo "✓ Agent is on chrome://flags page"
    else
        echo "⚠ Agent is not on chrome://flags page: $ACTIVE_URL"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# CRITICAL: Gracefully close Chrome to ensure Local State is persisted to disk
# Chrome saves experimental flags to Local State file, which requires proper shutdown
echo "Closing Chrome to save experimental flags configuration..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed (force kill if necessary)
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Wait a bit more for file system to flush
sleep 1

# Export Local State file to temporary location for verification
# Note: Local State is in the Chrome config root, NOT in the Default profile
echo "Exporting Chrome Local State file..."

CHROME_CONFIG="/home/ga/.config/google-chrome-cdp"
LOCAL_STATE_FILE="$CHROME_CONFIG/Local State"

if [ -f "$LOCAL_STATE_FILE" ]; then
    cp "$LOCAL_STATE_FILE" /tmp/local_state_export.json
    echo "✓ Local State exported to /tmp/local_state_export.json"
    
    # Show file size for debugging
    FILE_SIZE=$(stat -f%z "$LOCAL_STATE_FILE" 2>/dev/null || stat -c%s "$LOCAL_STATE_FILE" 2>/dev/null || echo "unknown")
    echo "  File size: $FILE_SIZE bytes"
    
    # Preview enabled experiments if jq is available
    if command -v jq &> /dev/null; then
        echo "  Enabled experiments:"
        jq -r '.browser.enabled_labs_experiments[]? // "none"' /tmp/local_state_export.json 2>/dev/null | head -10 || echo "  (could not parse)"
    fi
else
    echo "⚠ Warning: Local State file not found at $LOCAL_STATE_FILE"
    
    # Try alternative location
    ALT_CONFIG="/home/ga/.config/google-chrome"
    ALT_LOCAL_STATE="$ALT_CONFIG/Local State"
    
    if [ -f "$ALT_LOCAL_STATE" ]; then
        cp "$ALT_LOCAL_STATE" /tmp/local_state_export.json
        echo "✓ Local State exported from alternative location: $ALT_LOCAL_STATE"
    else
        echo "✗ Could not find Local State file in any known location"
        echo "  Tried: $LOCAL_STATE_FILE"
        echo "  Tried: $ALT_LOCAL_STATE"
        
        # List Chrome config directories for debugging
        echo "Chrome config directories:"
        ls -la /home/ga/.config/ | grep -i chrome || echo "  No Chrome directories found"
    fi
fi

# Also capture Preferences as secondary data source (though flags are in Local State)
PREFS_FILE="$CHROME_CONFIG/Default/Preferences"
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" /tmp/chrome_preferences_export.json 2>/dev/null || true
    echo "✓ Preferences also exported (secondary data)"
fi

echo "✅ Export complete"
echo "Local State file has been saved for verification"