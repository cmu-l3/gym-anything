#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Experimental Flag Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any pending changes are processed
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
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Kill Chrome to ensure Local State file is written to disk
# This is critical because experimental flags are stored in Local State
echo "Stopping Chrome to save Local State configuration..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Local State file to temporary location for verification
echo "Exporting Chrome Local State file..."

# Try primary location (chrome-cdp profile)
CHROME_CONFIG_DIR="/home/ga/.config/google-chrome-cdp"
if [ -f "$CHROME_CONFIG_DIR/Local State" ]; then
    cp "$CHROME_CONFIG_DIR/Local State" /tmp/local_state_export.json
    echo "✓ Local State exported from: $CHROME_CONFIG_DIR/Local State"
    echo "Local State file size: $(stat -c%s /tmp/local_state_export.json) bytes"
else
    echo "⚠ Warning: Local State not found at $CHROME_CONFIG_DIR/Local State"
    
    # Try alternative location (standard Chrome profile)
    CHROME_CONFIG_DIR_ALT="/home/ga/.config/google-chrome"
    if [ -f "$CHROME_CONFIG_DIR_ALT/Local State" ]; then
        cp "$CHROME_CONFIG_DIR_ALT/Local State" /tmp/local_state_export.json
        echo "✓ Local State exported from alternative location: $CHROME_CONFIG_DIR_ALT/Local State"
    else
        echo "✗ Could not find Local State file in any known location"
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/local_state_export.json
    fi
fi

# Also check if we can find any enabled experiments in the file
if [ -f /tmp/local_state_export.json ] && command -v jq &> /dev/null; then
    echo "Checking for enabled experiments..."
    EXPERIMENTS=$(jq -r '.browser.enabled_labs_experiments // [] | length' /tmp/local_state_export.json 2>/dev/null || echo "0")
    echo "Found $EXPERIMENTS enabled experiment(s) in Local State"
    
    if [ "$EXPERIMENTS" != "0" ]; then
        echo "Enabled experiments list:"
        jq -r '.browser.enabled_labs_experiments // []' /tmp/local_state_export.json 2>/dev/null || true
    fi
fi

echo "✅ Export complete"
echo "Local State file ready for verification"