#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools CSS Override Task Setup ==="
echo "Task: Use DevTools to modify CSS styles of heading element"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for image processing
pip3 install -q pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page
echo "Creating test HTML page..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/devtools_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevTools CSS Practice</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            background: #f5f5f5;
        }
        #main-heading {
            font-size: 48px;
            text-align: center;
            padding: 10px;
            /* Default styles - agent will override these using DevTools */
            background-color: white;
            color: black;
        }
    </style>
</head>
<body>
    <h1 id="main-heading">Welcome to DevTools Practice</h1>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/devtools_test_page.html"
echo "✓ Test HTML page created at: $TEST_PAGE_DIR/devtools_test_page.html"

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

# Navigate to the test page
TEST_PAGE_URL="file:///home/ga/Documents/devtools_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/devtools_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
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

# Take initial screenshot for before/after comparison
echo "Capturing initial screenshot..."
su - ga -c "DISPLAY=:1 import -window root /tmp/devtools_before.png" 2>/dev/null || true
if [ -f "/tmp/devtools_before.png" ]; then
    echo "✓ Initial screenshot saved to /tmp/devtools_before.png"
else
    echo "⚠ Warning: Could not capture initial screenshot"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the test page with default styling"
echo ""
echo "Agent should now:"
echo "  1. Press F12 (or Ctrl+Shift+I) to open DevTools"
echo "  2. Ensure Elements panel is active"
echo "  3. Select the h1#main-heading element"
echo "  4. In the Styles pane, add to element.style:"
echo "     - background-color: #FFD700 (or 'gold')"
echo "     - color: #1A1A4D (or similar dark blue)"
echo "  5. Verify changes appear in the page"