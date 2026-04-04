#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Audio Tab Muting Task Export: audio_tab_muting@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture current tab information via CDP while Chrome is still running
echo "Capturing current tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_final_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured final CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_final_tabs.json > /tmp/chrome_final_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_final_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s) at task completion"
    
    # Extract URLs for verification
    jq -r '.[] | .url' /tmp/chrome_final_page_tabs.json > /tmp/final_tab_urls.txt
    
    echo "Current tabs:"
    cat /tmp/final_tab_urls.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > /tmp/chrome_final_page_tabs.json
    touch /tmp/final_tab_urls.txt
fi

# Take a screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted
echo "Closing Chrome to save preferences and session state..."
pkill -TERM chrome || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for mute state verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
        cp "$CHROME_PROFILE_ALT/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file"
        echo "{}" > /tmp/chrome_preferences.json
    fi
fi

# Export session files for additional verification
echo "Exporting Chrome session data..."
for session_file in "Current Session" "Current Tabs" "Last Session" "Last Tabs"; do
    if [ -f "$CHROME_PROFILE/$session_file" ]; then
        cp "$CHROME_PROFILE/$session_file" "/tmp/chrome_${session_file// /_}.dat" 2>/dev/null || true
    fi
done

# Copy the initial state marker for verification
if [ -f "/tmp/audio_tab_url.txt" ]; then
    cp /tmp/audio_tab_url.txt /tmp/audio_tab_url_marker.txt
fi

echo "✅ Export complete"
echo "Files prepared for verification:"
echo "  - /tmp/chrome_final_page_tabs.json (CDP tab list)"
echo "  - /tmp/chrome_preferences.json (Chrome Preferences with mute settings)"
echo "  - /tmp/final_tab_urls.txt (List of tab URLs)"
echo "  - /tmp/audio_tab_url_marker.txt (Original audio tab URL)"