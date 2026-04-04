#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Lighthouse Audit Task Setup ==="
echo "Task: Run Lighthouse audit and export performance report"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for HTML/JSON parsing
pip3 install -q beautifulsoup4 lxml 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Target URL for Lighthouse audit
TARGET_URL="${TARGET_URL:-https://example.com}"
echo "Target URL for audit: $TARGET_URL"

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

# Navigate to the target URL
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 5

# Wait for page to fully load before opening DevTools
echo "Waiting for page to load completely..."
sleep 3

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

# Clear any existing Lighthouse reports from Downloads to avoid confusion
echo "Cleaning up old Lighthouse reports..."
rm -f /home/ga/Downloads/lighthouse*.html 2>/dev/null || true
rm -f /home/ga/Downloads/lighthouse*.json 2>/dev/null || true
rm -f /home/ga/Downloads/*report*.html 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome is ready with page loaded: $TARGET_URL"
echo ""
echo "Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Click on 'Lighthouse' tab (may be in >> overflow menu)"
echo "  3. Ensure 'Performance' and 'Accessibility' are checked"
echo "  4. Select 'Desktop' device (recommended)"
echo "  5. Click 'Analyze page load' button"
echo "  6. Wait 10-30 seconds for audit to complete"
echo "  7. Export report via menu (⋮) → 'Save as HTML' or 'Save as JSON'"
echo "  8. Save to Downloads folder with a descriptive filename"