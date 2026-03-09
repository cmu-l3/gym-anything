#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Flags Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Take a screenshot before any operations
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/flags_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/flags_screenshot.png"
fi

# Capture active tab URL via CDP for verification context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if we're still on chrome://flags page (might indicate agent didn't relaunch)
    if [[ "$ACTIVE_URL" == "chrome://flags"* ]]; then
        echo "⚠ Warning: Still on chrome://flags page - agent may not have clicked Relaunch button"
    fi
fi

# Wait a moment for Chrome to potentially complete relaunch
# The agent should have clicked Relaunch, which will restart Chrome
echo "Waiting for potential Chrome relaunch to complete..."
sleep 3

# Check if Chrome is running (it should be after relaunch)
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "✓ Chrome is running (relaunch may have completed)"
    
    # Focus Chrome window to ensure settings are synchronized
    wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
    if [ -n "$wid" ]; then
        su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
        sleep 1
    fi
else
    echo "⚠ Chrome is not running - it may still be relaunching"
    # Wait a bit more for relaunch to complete
    sleep 3
fi

# Export Local State file for flag verification
echo "Exporting Chrome Local State configuration..."
LOCAL_STATE_PATH="/home/ga/.config/google-chrome-cdp/Local State"

# Try primary location
if [ -f "$LOCAL_STATE_PATH" ]; then
    cp "$LOCAL_STATE_PATH" /tmp/chrome_local_state.json
    echo "✓ Local State exported to /tmp/chrome_local_state.json"
    
    # Display enabled experiments for debugging
    if command -v jq &> /dev/null; then
        echo "Current enabled experiments:"
        jq -r '.browser.enabled_labs_experiments // []' /tmp/chrome_local_state.json || echo "  (none or not parseable)"
    fi
else
    echo "⚠ Warning: Local State not found at $LOCAL_STATE_PATH"
    
    # Try alternative location
    ALT_LOCAL_STATE="/home/ga/.config/google-chrome/Local State"
    if [ -f "$ALT_LOCAL_STATE" ]; then
        cp "$ALT_LOCAL_STATE" /tmp/chrome_local_state.json
        echo "✓ Local State exported from alternative location"
    else
        echo "✗ Could not find Local State file in any known location"
        # Create empty file to prevent verifier errors
        echo "{}" > /tmp/chrome_local_state.json
    fi
fi

# Export Preferences as additional context (optional)
PREFS_PATH="/home/ga/.config/google-chrome-cdp/Default/Preferences"
if [ -f "$PREFS_PATH" ]; then
    cp "$PREFS_PATH" /tmp/chrome_preferences.json 2>/dev/null || true
fi

# Create a timestamp file to help verifier assess timing
date +%s > /tmp/export_timestamp.txt

echo "✅ Export complete"
echo "Verification files prepared in /tmp/"