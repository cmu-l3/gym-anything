#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Website Shortcut Creation Task Setup ==="
echo "Task: Create desktop shortcut for Wikipedia with 'Open as window' option"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Clean desktop directory to ensure fresh state
echo "Cleaning desktop for fresh start..."
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"
# Remove any existing Wikipedia-related desktop shortcuts
rm -f "$DESKTOP_DIR"/*ikipedia*.desktop 2>/dev/null || true
rm -f "$DESKTOP_DIR"/*.desktop 2>/dev/null || true
chown -R ga:ga "$DESKTOP_DIR"
echo "✓ Desktop directory prepared"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
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

# Navigate to Wikipedia
TARGET_URL="https://en.wikipedia.org/"
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait for page to fully load
echo "Waiting for Wikipedia to load..."
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check active tab URL
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "Active URL: $ACTIVE_URL"
    
    if [[ "$ACTIVE_URL" == *"wikipedia.org"* ]]; then
        echo "✓ Wikipedia page loaded successfully"
    else
        echo "⚠ Warning: Active URL doesn't contain wikipedia.org"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying Wikipedia. Agent should now:"
echo "  1. Click the three-dot menu (⋮) in top-right corner"
echo "  2. Navigate to 'More tools' → 'Create shortcut...'"
echo "  3. Enter name 'Wikipedia' in the dialog"
echo "  4. Check the 'Open as window' checkbox"
echo "  5. Click 'Create' button"