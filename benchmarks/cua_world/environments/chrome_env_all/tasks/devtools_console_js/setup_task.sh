#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Console JavaScript Execution Task Setup ==="
echo "Task: Use DevTools Console to modify webpage with JavaScript"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for verification
pip3 install -q pillow numpy requests 2>/dev/null || true

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
    <title>DevTools Console Practice</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            padding: 40px;
            margin: 0;
            background-color: #f5f5f5;
        }
        #main-heading {
            font-size: 2.5em;
            margin-bottom: 30px;
            color: #333;
            font-weight: 600;
        }
        .content-box {
            padding: 20px;
            border: 2px solid #ddd;
            border-radius: 8px;
            background-color: white;
            max-width: 600px;
            line-height: 1.6;
        }
        .content-box p {
            margin: 10px 0;
        }
        .instructions {
            margin-top: 30px;
            padding: 15px;
            background-color: #e8f4f8;
            border-left: 4px solid #0066cc;
            border-radius: 4px;
        }
        .instructions h3 {
            margin-top: 0;
            color: #0066cc;
        }
    </style>
</head>
<body>
    <h1 id="main-heading">Welcome</h1>
    <div class="content-box">
        <p><strong>DevTools Console Practice Page</strong></p>
        <p>This page is designed for practicing Chrome Developer Tools Console.</p>
        <p>Use the Console tab to execute JavaScript and modify this page!</p>
    </div>
    
    <div class="instructions">
        <h3>Instructions:</h3>
        <p>1. Press <strong>F12</strong> to open DevTools</p>
        <p>2. Click on the <strong>Console</strong> tab</p>
        <p>3. Execute JavaScript to modify the page elements</p>
        <p>4. Try changing the heading text, colors, and backgrounds!</p>
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

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Verify the test page loaded correctly
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"devtools_test_page.html"* ]]; then
        echo "✓ Test page loaded successfully"
    else
        echo "⚠ Warning: Test page may not have loaded. Current URL: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Store original page state for verification
echo "Capturing original page state..."
curl -s http://localhost:9222/json > /tmp/original_tabs.json 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome is displaying the DevTools practice page"
echo "Agent should now:"
echo "  1. Press F12 to open Developer Tools"
echo "  2. Click on Console tab"
echo "  3. Execute: document.getElementById('main-heading').textContent = 'Hello Developer!';"
echo "  4. Execute: document.getElementById('main-heading').style.color = 'blue';"
echo "  5. Execute: document.querySelector('.content-box').style.backgroundColor = '#fffacd';"