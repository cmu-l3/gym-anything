#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Autofill Address Configuration Task Setup ==="
echo "Task: Add a complete address entry to Chrome autofill settings"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and ready
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

# Navigate to the starting URL (Google homepage)
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
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check current autofill profiles for baseline
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    echo "Backing up current Preferences..."
    cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_autofill" || true
    
    # Log current autofill profile count
    PROFILE_COUNT=$(jq '.autofill.profiles | length // 0' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
    echo "Current autofill profiles: $PROFILE_COUNT"
else
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$CHROME_PROFILE/Preferences.backup_autofill" || true
        PROFILE_COUNT=$(jq '.autofill.profiles | length // 0' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
        echo "Current autofill profiles: $PROFILE_COUNT"
    fi
fi

echo "=== Setup complete ==="
echo "Chrome is ready on Google homepage"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings or use Settings menu (⋮ → Settings)"
echo "  2. Search for 'autofill' or navigate to 'Autofill and passwords'"
echo "  3. Click 'Addresses and more'"
echo "  4. Click 'Add' button to create new address"
echo "  5. Fill in the following details:"
echo "     - Full name: John Anderson"
echo "     - Organization: Tech Innovations Inc"
echo "     - Street address: 742 Evergreen Terrace"
echo "     - City: Springfield"
echo "     - State: IL (or Illinois)"
echo "     - ZIP code: 62701"
echo "     - Country: United States"
echo "     - Phone: 555-0123"
echo "     - Email: john.anderson@techinnovations.com"
echo "  6. Click 'Save' to persist the address"