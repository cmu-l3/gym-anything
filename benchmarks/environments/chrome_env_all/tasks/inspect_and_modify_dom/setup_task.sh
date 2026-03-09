#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Developer Tools DOM Inspection Task Setup ==="
echo "Task: Inspect button element and change background color to green"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for verification
pip3 install -q pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page
echo "Creating test HTML page..."
TEST_PAGE_DIR="/tmp"
TEST_PAGE_PATH="$TEST_PAGE_DIR/devtools_test_page.html"

cat > "$TEST_PAGE_PATH" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevTools Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 50px;
            text-align: center;
            background-color: #f5f5f5;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        .instruction {
            color: #666;
            font-size: 14px;
            margin-bottom: 30px;
        }
        button {
            background-color: #007bff;
            color: white;
            padding: 15px 40px;
            font-size: 20px;
            font-weight: bold;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-top: 20px;
        }
        button:hover {
            opacity: 0.9;
        }
    </style>
</head>
<body>
    <h1>Welcome to Our Site</h1>
    <p class="instruction">This is a test page for Developer Tools practice.</p>
    <button id="subscribe-btn">Subscribe Now</button>
</body>
</html>
EOF

echo "✓ Test HTML page created at: $TEST_PAGE_PATH"

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
TEST_PAGE_URL="file://$TEST_PAGE_PATH"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_PAGE_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Check current page URL
    CURRENT_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""' 2>/dev/null || echo "")
    echo "✓ Current URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Save original button color for reference
echo "#007bff" > /tmp/original_button_color.txt

echo "=== Setup complete ==="
echo "Chrome should be displaying the test page with a blue 'Subscribe Now' button"
echo ""
echo "Agent should now:"
echo "  1. Press F12 (or Ctrl+Shift+I) to open Developer Tools"
echo "  2. Click the element inspector icon (or press Ctrl+Shift+C)"
echo "  3. Click on the 'Subscribe Now' button to inspect it"
echo "  4. In the Styles pane, find or add background-color property"
echo "  5. Change the value to #28a745 (green)"
echo "  6. Verify the button turns green on the page"