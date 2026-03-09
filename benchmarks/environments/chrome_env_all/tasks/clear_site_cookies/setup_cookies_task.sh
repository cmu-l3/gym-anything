#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Cookie Deletion Task Setup ==="
echo "Task: Delete cookies for httpbin.org while preserving others"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for SQLite handling
pip3 install -q 2>/dev/null || true

# Wait for environment to be ready
sleep 2

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

# Navigate to httpbin.org to set target cookies
echo "Step 1: Creating target cookies on httpbin.org..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://httpbin.org/cookies/set?test_cookie=delete_me&session=test123'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Verify cookies were set by visiting cookies endpoint
echo "Verifying httpbin.org cookies..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://httpbin.org/cookies'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Navigate to example.com to set control cookies
echo "Step 2: Creating control cookies on example.com..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://example.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Navigate to google.com for additional control cookies
echo "Step 3: Creating control cookies on google.com..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Navigate to wikipedia.org for more control cookies (some sites may block cookies in automation)
echo "Step 4: Creating additional control cookies on wikipedia.org..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.wikipedia.org'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Close extra tabs to reduce clutter, keeping only one tab
echo "Closing extra tabs..."
for i in {1..3}; do
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
    sleep 0.5
done

# Navigate to starting URL (Google homepage as neutral starting point)
echo "Navigating to starting page..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Check that cookies were actually created (optional debug info)
echo "Checking initial cookie state..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    COOKIE_COUNT=$(sqlite3 "$CHROME_PROFILE/Cookies" "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%httpbin.org%';" 2>/dev/null || echo "0")
    echo "✓ httpbin.org cookies in database: $COOKIE_COUNT"
    
    TOTAL_COOKIES=$(sqlite3 "$CHROME_PROFILE/Cookies" "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "0")
    echo "✓ Total cookies in database: $TOTAL_COOKIES"
else
    echo "⚠ Cookies database not yet accessible (Chrome may still be writing)"
fi

echo "=== Setup complete ==="
echo ""
echo "Initial state: Cookies created for httpbin.org, example.com, google.com, wikipedia.org"
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://settings/cookies (or Settings → Privacy and security → Cookies)"
echo "  2. Click on 'See all site data and permissions'"
echo "  3. Search for 'httpbin.org' in the search box"
echo "  4. Click the trash/remove icon next to httpbin.org"
echo "  5. Confirm deletion if prompted"
echo ""
echo "Success criteria: httpbin.org cookies deleted, other site cookies preserved"