#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Cookie Management Task Setup ==="
echo "Task: Navigate to site data settings and selectively clear github.com cookies"

# Install required utilities
echo "Installing required utilities..."
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for verification
pip3 install -q 2>/dev/null || true

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
sleep 3

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

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Navigate to multiple sites to create cookies
echo "Creating initial cookies by visiting sites..."

# Site 1: example.com
echo "Navigating to: https://example.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://example.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Site 2: github.com (target for deletion)
echo "Navigating to: https://github.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://github.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Site 3: wikipedia.org
echo "Navigating to: https://wikipedia.org"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://wikipedia.org'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Navigate back to Google homepage as starting point
echo "Navigating back to starting page: https://www.google.com"
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

# Verify initial cookie state
echo "Verifying initial cookie state..."
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

# Check which profile is being used
if [ -f "$CHROME_PROFILE_CDP/Cookies" ]; then
    COOKIES_PATH="$CHROME_PROFILE_CDP/Cookies"
    echo "✓ Found Cookies database at: $COOKIES_PATH"
elif [ -f "$CHROME_PROFILE/Cookies" ]; then
    COOKIES_PATH="$CHROME_PROFILE/Cookies"
    echo "✓ Found Cookies database at: $COOKIES_PATH"
else
    echo "⚠ Warning: Cookies database not found"
    COOKIES_PATH=""
fi

# Count initial cookies for each domain (if sqlite3 available)
if [ -n "$COOKIES_PATH" ] && command -v sqlite3 &> /dev/null; then
    echo "Initial cookie counts:"
    
    # Need to copy database because it might be locked
    cp "$COOKIES_PATH" /tmp/cookies_check.db 2>/dev/null || true
    
    if [ -f /tmp/cookies_check.db ]; then
        GITHUB_COUNT=$(sqlite3 /tmp/cookies_check.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%github.com%';" 2>/dev/null || echo "0")
        EXAMPLE_COUNT=$(sqlite3 /tmp/cookies_check.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%example.com%';" 2>/dev/null || echo "0")
        WIKI_COUNT=$(sqlite3 /tmp/cookies_check.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%wikipedia.org%';" 2>/dev/null || echo "0")
        
        echo "  github.com: $GITHUB_COUNT cookies"
        echo "  example.com: $EXAMPLE_COUNT cookies"
        echo "  wikipedia.org: $WIKI_COUNT cookies"
        
        rm /tmp/cookies_check.db
    fi
fi

echo "=== Setup complete ==="
echo "Chrome is ready with cookies from multiple sites."
echo ""
echo "Agent task:"
echo "  1. Open Chrome Settings (chrome://settings or menu)"
echo "  2. Navigate to: Privacy and security → Cookies and other site data"
echo "  3. Click 'See all site data and permissions'"
echo "  4. Search for 'github.com' in the search box"
echo "  5. Click the trash/remove icon next to github.com entry"
echo "  6. Confirm deletion if prompted"
echo ""
echo "Expected outcome:"
echo "  - github.com cookies should be deleted"
echo "  - example.com cookies should remain"
echo "  - wikipedia.org cookies should remain"