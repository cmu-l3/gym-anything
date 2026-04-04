#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Zoom Adjustment Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure changes are finalized
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture current page URL and title via CDP before closing
echo "Capturing active tab information..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    echo "$ACTIVE_TITLE" > /tmp/final_title.txt
else
    echo "⚠ Warning: Could not capture CDP information"
fi

# Take a screenshot showing the zoom indicator
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_zoom.png" 2>/dev/null || true
    echo "✓ Screenshot saved to /tmp/final_screenshot_zoom.png"
fi

# Close Chrome gracefully to ensure preferences are written to disk
echo "Closing Chrome to save zoom settings..."
pkill -f "google-chrome" || pkill -f "chromium" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || pkill -9 -f "chromium" || true
    sleep 1
fi

# Wait a bit more to ensure file system writes complete
sleep 1

# Export Chrome Preferences file containing zoom settings
echo "Exporting Chrome Preferences with zoom data..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_zoom_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_zoom_preferences.json"
    
    # Show file size and modification time for debugging
    ls -lh "$CHROME_PROFILE/Preferences" || true
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_zoom_preferences.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE"
    else
        echo "✗ Could not find Preferences file in any known location"
        # Create empty file to prevent verifier errors
        echo "{}" > /tmp/chrome_zoom_preferences.json
    fi
fi

# Extract and display zoom information for debugging
if [ -f /tmp/chrome_zoom_preferences.json ]; then
    echo ""
    echo "Extracting zoom settings from Preferences..."
    
    # Try to extract per-host zoom levels (these are where zoom is stored)
    if command -v jq &> /dev/null; then
        echo "Per-host zoom levels:"
        jq -r '.partition.per_host_zoom_levels // {} | to_entries[] | "\(.key): \(.value)"' /tmp/chrome_zoom_preferences.json 2>/dev/null || true
        jq -r '.profile.per_host_zoom_levels // {} | to_entries[] | "\(.key): \(.value)"' /tmp/chrome_zoom_preferences.json 2>/dev/null || true
        
        # Also check for default zoom level
        DEFAULT_ZOOM=$(jq -r '.partition.default_zoom_level // .profile.default_zoom_level // "not_set"' /tmp/chrome_zoom_preferences.json 2>/dev/null)
        echo "Default zoom level: $DEFAULT_ZOOM"
    fi
fi

echo ""
echo "✅ Export complete"
echo "Verification files ready at /tmp/"