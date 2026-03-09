#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Console DOM Manipulation Task Setup ==="
echo "Task: Use Console to execute JavaScript that modifies the DOM"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install websocket client for CDP communication
pip3 install -q websocket-client 2>/dev/null || true

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
    <title>DevTools Console Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 40px;
            background-color: #ffffff;
            margin: 0;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        p {
            color: #666;
            font-size: 16px;
            line-height: 1.6;
            max-width: 600px;
        }
        .instructions {
            background-color: #f0f0f0;
            padding: 20px;
            margin-top: 30px;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <h1>Console Test Page</h1>
    <p>This is a test paragraph. Use the Chrome DevTools Console to modify this page by executing JavaScript commands!</p>
    
    <div class="instructions">
        <h3>Instructions:</h3>
        <ul>
            <li>Open DevTools (Press F12)</li>
            <li>Navigate to the Console tab</li>
            <li>Execute JavaScript commands to modify the page</li>
        </ul>
    </div>
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

# Close any extra tabs to ensure clean state
echo "Closing extra tabs..."
TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
while [ "$TAB_COUNT" -gt 1 ]; do
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
    sleep 0.5
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
done

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "unknown")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the test page: devtools_test_page.html"
echo ""
echo "Agent should now:"
echo "  1. Press F12 to open Chrome DevTools"
echo "  2. Click on the 'Console' tab"
echo "  3. Execute: document.body.style.backgroundColor = '#2196F3';"
echo "  4. Execute: document.querySelector('h1').textContent = 'DevTools Console Success!';"
echo "  5. Execute: document.querySelector('p').style.fontSize = '24px';"