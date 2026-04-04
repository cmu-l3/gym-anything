#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Pinning Task Export: tab_pin_organize@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP before closing Chrome
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_final.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_final.json > /tmp/chrome_page_tabs_final.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_final.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for verification
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/chrome_page_tabs_final.json > /tmp/tab_list_final.txt
    
    echo "Tab information:"
    cat /tmp/tab_list_final.txt | head -10
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > /tmp/chrome_page_tabs_final.json
    touch /tmp/tab_list_final.txt
fi

# Take a screenshot before closing Chrome
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/tabs_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/tabs_screenshot.png"
fi

# Give Chrome a moment to sync session state
sleep 2

# Now close Chrome gracefully to ensure session files are written
echo "Closing Chrome to save session state..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 0.5

# Try graceful close first
pkill -TERM chrome 2>/dev/null || true
sleep 3

# Check if Chrome is still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, forcing close..."
    pkill -9 chrome 2>/dev/null || true
    sleep 2
fi

echo "Chrome closed"

# Copy Chrome session files for pinned tab verification
echo "Exporting Chrome session files..."

CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Try to copy Current Session
if [ -f "$CHROME_PROFILE/Current Session" ]; then
    cp "$CHROME_PROFILE/Current Session" /tmp/chrome_current_session 2>/dev/null || true
    echo "✓ Current Session exported"
elif [ -f "$ALT_PROFILE/Current Session" ]; then
    cp "$ALT_PROFILE/Current Session" /tmp/chrome_current_session 2>/dev/null || true
    echo "✓ Current Session exported (alt location)"
else
    echo "⚠ Current Session file not found"
fi

# Try to copy Last Session as fallback
if [ -f "$CHROME_PROFILE/Last Session" ]; then
    cp "$CHROME_PROFILE/Last Session" /tmp/chrome_last_session 2>/dev/null || true
    echo "✓ Last Session exported"
elif [ -f "$ALT_PROFILE/Last Session" ]; then
    cp "$ALT_PROFILE/Last Session" /tmp/chrome_last_session 2>/dev/null || true
    echo "✓ Last Session exported (alt location)"
fi

# Copy Preferences as additional verification source
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_final.json 2>/dev/null || true
    echo "✓ Preferences exported"
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_final.json 2>/dev/null || true
    echo "✓ Preferences exported (alt location)"
fi

# Record session file statistics
if [ -f "/tmp/chrome_current_session" ]; then
    stat /tmp/chrome_current_session > /tmp/session_stats.txt 2>/dev/null || true
    ls -lh /tmp/chrome_current_session
fi

echo "✅ Export complete"
echo "Exported files:"
ls -lh /tmp/chrome_*_final.json /tmp/chrome_*session /tmp/tab_*.txt 2>/dev/null | head -20