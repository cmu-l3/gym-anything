#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Payment Method Autofill Configuration Task Setup ==="
echo "Task: Add credit card to Chrome's payment methods for autofill"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python SQLite libraries (usually built-in, but ensure availability)
pip3 install -q --upgrade pip 2>/dev/null || true

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

# Clear any existing test payment methods with the same name to avoid duplicates
echo "Cleaning up any existing test payment methods..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Find the correct profile location
if [ -f "$CHROME_PROFILE/Web Data" ]; then
    WEB_DATA_PATH="$CHROME_PROFILE/Web Data"
elif [ -f "$ALT_PROFILE/Web Data" ]; then
    WEB_DATA_PATH="$ALT_PROFILE/Web Data"
else
    echo "⚠ Warning: Could not find Web Data database for cleanup"
    WEB_DATA_PATH=""
fi

if [ -n "$WEB_DATA_PATH" ]; then
    # Close Chrome temporarily to access Web Data database
    echo "Temporarily closing Chrome to clean database..."
    pkill -f "google-chrome" || true
    sleep 2
    
    # Remove any existing test entries
    sqlite3 "$WEB_DATA_PATH" "DELETE FROM credit_cards WHERE name_on_card = 'Alex Chen';" 2>/dev/null || true
    echo "✓ Cleaned up any existing test entries"
    
    # Restart Chrome
    echo "Restarting Chrome..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
    
    # Re-focus Chrome
    wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
    if [ -n "$wid" ]; then
        wmctrl -i -a $wid || true
        sleep 1
    fi
fi

# Record the task start timestamp for verification
date +%s > /tmp/task_start_timestamp.txt
echo "✓ Task start timestamp recorded"

echo "=== Setup complete ==="
echo "Chrome is ready. Agent should navigate to chrome://settings/payments and add payment method."
echo ""
echo "Expected actions:"
echo "  1. Navigate to chrome://settings/payments or Settings > Payment methods"
echo "  2. Click 'Add' button to add a payment method"
echo "  3. Fill in card details:"
echo "     - Cardholder name: Alex Chen"
echo "     - Card number: 4532 1488 0343 6467"
echo "     - Expiration month: 12"
echo "     - Expiration year: 2027"
echo "  4. Click 'Save' to store the payment method"