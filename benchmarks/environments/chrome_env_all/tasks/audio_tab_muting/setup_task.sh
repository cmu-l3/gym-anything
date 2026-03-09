#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Audio Tab Muting Task Setup: audio_tab_muting@1 ==="
echo "Task: Identify and mute the tab playing audio among multiple open tabs"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Kill any existing Chrome instances to start fresh
echo "Cleaning up any existing Chrome instances..."
pkill -9 chrome || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome-cdp

echo "Starting Chrome with multiple tabs..."

# Build URL list for multiple tabs
# The 4th tab will be YouTube with autoplay enabled
URLS=(
    "https://docs.google.com/document"
    "https://github.com/trending"
    "https://stackoverflow.com/questions"
    "https://www.youtube.com/watch?v=jfKfPfyJRdk&autoplay=1"
    "https://mail.google.com"
    "https://en.wikipedia.org/wiki/Machine_learning"
    "https://news.ycombinator.com"
    "https://www.reddit.com/r/programming"
)

# Start Chrome with all tabs
echo "Launching Chrome with ${#URLS[@]} tabs..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh '${URLS[0]}'" &
sleep 5

# Wait for Chrome to be ready
sleep 3

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
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

# Open additional tabs using Ctrl+T and navigation
for i in "${!URLS[@]}"; do
    if [ $i -eq 0 ]; then
        # First URL already opened
        continue
    fi
    
    URL="${URLS[$i]}"
    echo "Opening tab $((i+1)): $URL"
    
    # Open new tab
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 1
    
    # Type URL in address bar
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$URL'" || true
    sleep 0.5
    
    # Press Enter
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    
    # Wait longer for YouTube tab to load audio
    if [ $i -eq 3 ]; then
        sleep 5
        echo "✓ YouTube audio tab loaded (should be playing audio)"
    else
        sleep 2
    fi
done

# Navigate back to first tab to make audio tab less obvious
echo "Switching to first tab to simulate background audio..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Chrome has $TAB_COUNT tab(s) open"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Save initial tab information for verification
echo "Saving initial Chrome state..."
curl -s http://localhost:9222/json > /tmp/chrome_initial_tabs.json 2>/dev/null || true

# Create a marker file with the audio tab URL for verification
echo "https://www.youtube.com/watch?v=jfKfPfyJRdk" > /tmp/audio_tab_url.txt

echo "=== Setup complete ==="
echo "Chrome is running with ${#URLS[@]} tabs, one playing audio (YouTube)"
echo ""
echo "Agent task:"
echo "  1. Scan tab bar for speaker/audio indicator icon"
echo "  2. Identify which tab is playing audio"
echo "  3. Right-click on that tab → 'Mute tab'"
echo "  4. OR close the audio tab (less preferred but acceptable)"
echo ""
echo "Expected audio source: YouTube (position 4 in tab bar)"