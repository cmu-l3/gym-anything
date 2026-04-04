#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Session Restore After Crash Task Setup ==="
echo "Task: Simulate browser crash and test session restoration"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Define the URLs for the research session that will be "crashed"
declare -a SESSION_URLS=(
    "https://en.wikipedia.org/wiki/Web_browser"
    "https://developer.mozilla.org/en-US/docs/Web/API"
    "https://stackoverflow.com/questions/tagged/chrome"
    "https://www.google.com/search?q=chrome+session+restore"
    "https://github.com/topics/browser-automation"
)

# Store expected session URLs for verifier
echo "Storing expected session state for verification..."
printf '%s\n' "${SESSION_URLS[@]}" > /tmp/expected_session_urls.txt
echo "✓ Expected URLs saved to /tmp/expected_session_urls.txt"

# Ensure Chrome is NOT running initially
echo "Ensuring clean Chrome state..."
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Verify Chrome is fully stopped
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Warning: Chrome still running, force killing..."
    pkill -9 chrome || true
    sleep 2
fi

# Check for existing Chrome launch script
if [ ! -f "/home/ga/launch_chrome.sh" ]; then
    echo "Warning: Chrome launch script not found at /home/ga/launch_chrome.sh"
    echo "Creating basic launch script..."
    
    cat > /home/ga/launch_chrome.sh << 'EOFLAUNCH'
#!/bin/bash
google-chrome-stable \
    --remote-debugging-port=1337 \
    --no-first-run \
    --no-default-browser-check \
    --disable-background-networking \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-breakpad \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-dev-shm-usage \
    --disable-extensions \
    --disable-features=site-per-process \
    --disable-hang-monitor \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --disable-sync \
    --disable-translate \
    --metrics-recording-only \
    --no-sandbox \
    --safebrowsing-disable-auto-update \
    --user-data-dir=/home/ga/.config/google-chrome-cdp \
    "$@" \
    > /tmp/chrome_ga.log 2>&1 &
EOFLAUNCH
    
    chmod +x /home/ga/launch_chrome.sh
    chown ga:ga /home/ga/launch_chrome.sh
fi

# Launch Chrome with multiple tabs for the "research session"
echo "Launching Chrome with research session (${#SESSION_URLS[@]} tabs)..."

# Start Chrome with first URL
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh '${SESSION_URLS[0]}'" &
sleep 6

# Wait for Chrome to be fully ready
echo "Waiting for Chrome to initialize..."
for i in {1..15}; do
    if curl -s http://localhost:9222/json > /dev/null 2>&1; then
        echo "✓ Chrome CDP is ready"
        break
    fi
    sleep 1
done

# Verify Chrome is accessible
if ! curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "⚠ Warning: Chrome CDP not responding after launch"
fi

sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
echo "Activating desktop..."
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

# Open additional tabs with remaining URLs
echo "Opening additional tabs for session..."
for i in {1..4}; do
    url="${SESSION_URLS[$i]}"
    echo "Opening tab $((i+1)): $url"
    
    # Focus Chrome
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.3
    
    # Open new tab
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 0.8
    
    # Navigate to URL
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 2.5
done

# Give pages time to fully load
echo "Waiting for all tabs to load..."
sleep 3

# Verify all tabs are open via CDP
TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "0")
echo "✓ Chrome has $TAB_COUNT tab(s) open (expected ${#SESSION_URLS[@]})"

# Take a screenshot before crash for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/pre_crash_screenshot.png" 2>/dev/null || true
    echo "Pre-crash screenshot saved"
fi

# Store timestamp of crash for verification
date +%s > /tmp/crash_timestamp.txt

echo ""
echo "=== SIMULATING BROWSER CRASH ==="
echo "Force-killing Chrome with SIGKILL to simulate abnormal termination..."

# Force quit Chrome to simulate crash (SIGKILL - no cleanup)
pkill -9 -f "google-chrome" || true
pkill -9 -f "chrome.*remote-debugging-port" || true

# Wait for Chrome to fully terminate
sleep 3

# Verify Chrome is stopped
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Warning: Chrome still running, attempting additional kill..."
    pkill -9 chrome || true
    sleep 2
fi

# Double-check Chrome is fully dead
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "✓ Chrome successfully terminated (crash simulated)"
else
    echo "⚠ Warning: Chrome may still be running"
fi

# Ensure socat for CDP forwarding is still running (if used)
if ! pgrep socat > /dev/null; then
    echo "Starting socat for CDP forwarding..."
    socat TCP-LISTEN:9222,fork,reuseaddr TCP:localhost:1337 > /tmp/socat_cdp.log 2>&1 &
    sleep 1
fi

echo ""
echo "=== Crash Scenario Complete ==="
echo ""
echo "Chrome has been forcefully terminated with ${#SESSION_URLS[@]} tabs open."
echo "Session URLs:"
for i in "${!SESSION_URLS[@]}"; do
    echo "  $((i+1)). ${SESSION_URLS[$i]}"
done
echo ""
echo "Agent task:"
echo "  1. Launch Chrome (it will detect abnormal shutdown)"
echo "  2. Click 'Restore' button when prompted"
echo "  3. OR use History → Recently Closed if restore prompt missed"
echo "  4. Verify all ${#SESSION_URLS[@]} tabs are restored"
echo ""
echo "=== Agent should now begin task execution ==="