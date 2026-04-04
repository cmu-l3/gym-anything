#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Search Engine Configuration Task Setup ==="
echo "Task: Change default search engine from Google to DuckDuckGo"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install jq if not present (for JSON manipulation)
if ! command -v jq &> /dev/null; then
# apt-get install -y -qq jq || true
fi

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Reset search engine to Google (default) to ensure clean starting state
echo "Resetting search engine to Google (default starting state)..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
PREFS_FILE="$CHROME_PROFILE/Preferences"

# Try alternative location if primary doesn't exist
if [ ! -f "$PREFS_FILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    PREFS_FILE="$CHROME_PROFILE/Preferences"
fi

if [ -f "$PREFS_FILE" ]; then
    # Backup current preferences
    cp "$PREFS_FILE" "$PREFS_FILE.backup_$(date +%s)" 2>/dev/null || true
    
    # Reset search engine to Google using jq
    # We set the default_search_provider_data to Google's configuration
    TMP_PREFS=$(mktemp)
    jq '.default_search_provider_data.keyword = "google.com" | 
        .default_search_provider_data.short_name = "Google" |
        .default_search_provider_data.name = "Google" |
        .default_search_provider_data.search_url = "https://www.google.com/search?q={searchTerms}"' \
        "$PREFS_FILE" > "$TMP_PREFS" 2>/dev/null || true
    
    if [ -s "$TMP_PREFS" ]; then
        mv "$TMP_PREFS" "$PREFS_FILE"
        chown ga:ga "$PREFS_FILE"
        echo "✓ Search engine reset to Google"
    else
        rm -f "$TMP_PREFS"
        echo "⚠ Could not reset search engine, continuing anyway..."
    fi
else
    echo "⚠ Preferences file not found at $PREFS_FILE"
fi

# Restart Chrome to apply preference changes
echo "Restarting Chrome to apply default settings..."
pkill -f "google-chrome" || true
sleep 2

# Start Chrome fresh
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Re-focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -n "$wid" ]; then
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the starting URL (Google homepage as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with Google as default search engine"
echo ""
echo "Agent task instructions:"
echo "  1. Navigate to chrome://settings (type in address bar or use Chrome menu)"
echo "  2. Use settings search or scroll to find 'Search engine' section"
echo "  3. Click on the dropdown showing current search engine (Google)"
echo "  4. Select 'DuckDuckGo' from the list"
echo "  5. Chrome will automatically save the change"
echo ""
echo "Expected outcome: Preferences file will contain DuckDuckGo as default_search_provider_data"