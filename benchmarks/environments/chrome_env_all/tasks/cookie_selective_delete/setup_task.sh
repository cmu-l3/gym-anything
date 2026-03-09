#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Cookie Selective Deletion Task Setup ==="
echo "Task: Selectively delete tracking cookies while preserving functional cookies"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 sqlite3 || true

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

# Step 1: Navigate to httpbin.org to set initial cookies
echo "Navigating to httpbin.org to set test cookies..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://httpbin.org'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Step 2: Set cookies using httpbin's cookie setting endpoint
echo "Setting test cookies via httpbin.org/cookies/set..."

# Set session_id cookie
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://httpbin.org/cookies/set/session_id/abc123'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Set user_pref cookie
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://httpbin.org/cookies/set/user_pref/dark_mode'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Set tracking_id cookie
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://httpbin.org/cookies/set/tracking_id/xyz789'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Set analytics_token cookie
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://httpbin.org/cookies/set/analytics_token/track123'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Navigate to main httpbin page to verify cookies are set
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://httpbin.org/cookies'" || true
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

# Verify cookies were set by checking current page
echo "Verifying initial cookie setup..."
ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
if [[ "$ACTIVE_URL" == *"httpbin.org"* ]]; then
    echo "✓ Currently on httpbin.org"
else
    echo "⚠ Warning: Not on httpbin.org page"
fi

# Create a backup of cookies for verification purposes
echo "Creating initial cookie snapshot..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    cp "$CHROME_PROFILE/Cookies" /tmp/cookies_initial.db 2>/dev/null || true
    echo "✓ Initial cookies snapshot saved"
    
    # Query to verify cookies were set
    COOKIE_COUNT=$(sqlite3 /tmp/cookies_initial.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%httpbin.org%';" 2>/dev/null || echo "0")
    echo "✓ Found $COOKIE_COUNT cookies for httpbin.org domain"
else
    echo "⚠ Warning: Could not access Cookies database"
fi

echo "=== Setup complete ==="
echo "Chrome is on httpbin.org with 4 test cookies set:"
echo "  - session_id=abc123 (keep)"
echo "  - user_pref=dark_mode (keep)"
echo "  - tracking_id=xyz789 (DELETE)"
echo "  - analytics_token=track123 (DELETE)"
echo ""
echo "Agent should:"
echo "  1. Open Chrome Settings (chrome://settings)"
echo "  2. Navigate to: Privacy and security > Cookies and other site data"
echo "  3. Click 'See all site data and permissions'"
echo "  4. Search for 'httpbin.org'"
echo "  5. Click on httpbin.org to expand cookies"
echo "  6. Delete ONLY tracking_id and analytics_token"
echo "  7. Keep session_id and user_pref intact"