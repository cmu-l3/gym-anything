#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Lighthouse Accessibility Audit Task Setup ==="
echo "Task: Run Lighthouse accessibility audit and export results"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for parsing (in case they're needed)
pip3 install -q beautifulsoup4 lxml 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
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

# Navigate to the test page (W3C accessibility demo page - known to have issues)
TARGET_URL="https://www.w3.org/WAI/demos/bad/before/home.html"
echo "Navigating to test page: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait for page to fully load before agent can run audit
echo "Waiting for page to load completely..."
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Ensure Downloads directory exists and is empty of previous lighthouse reports
echo "Preparing Downloads directory..."
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"
# Remove any existing lighthouse reports to avoid confusion
find "$DOWNLOADS_DIR" -name "*accessibility*audit*.json" -type f -delete 2>/dev/null || true
find "$DOWNLOADS_DIR" -name "*lighthouse*.json" -type f -delete 2>/dev/null || true
find "$DOWNLOADS_DIR" -name "*accessibility*audit*.html" -type f -delete 2>/dev/null || true
find "$DOWNLOADS_DIR" -name "*lighthouse*.html" -type f -delete 2>/dev/null || true
chown -R ga:ga "$DOWNLOADS_DIR" || true

echo "=== Setup complete ==="
echo "Test page loaded: $TARGET_URL"
echo ""
echo "Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Click on the 'Lighthouse' tab in DevTools"
echo "  3. Select 'Accessibility' category (may deselect others)"
echo "  4. Select 'Desktop' device mode"
echo "  5. Click 'Analyze page load' or 'Generate report'"
echo "  6. Wait for audit to complete (~10-30 seconds)"
echo "  7. Click download/export icon to save report"
echo "  8. Save as: accessibility_audit_report.json (or .html)"
echo ""
echo "Note: The test page intentionally has accessibility issues for testing purposes"