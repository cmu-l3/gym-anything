#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DOM Element Screenshot Task Setup: element_screenshot@1 ==="
echo "Task: Capture screenshot of specific DOM element using DevTools"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for image processing
pip3 install -q Pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create test HTML page with target element
echo "Creating test HTML page with target element..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/element_screenshot_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Element Screenshot Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 40px;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            min-height: 100vh;
            margin: 0;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            color: #2c3e50;
            text-align: center;
            margin-bottom: 30px;
        }
        .instruction {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        #target-card {
            width: 450px;
            padding: 35px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 16px;
            color: white;
            box-shadow: 0 15px 50px rgba(0,0,0,0.3);
            margin: 50px auto;
            position: relative;
        }
        #target-card::before {
            content: '🎯';
            position: absolute;
            top: -20px;
            right: -20px;
            font-size: 40px;
        }
        #target-card h2 {
            margin: 0 0 20px 0;
            font-size: 28px;
            font-weight: bold;
        }
        #target-card p {
            margin: 0;
            line-height: 1.8;
            opacity: 0.95;
            font-size: 16px;
        }
        .footer {
            text-align: center;
            margin-top: 50px;
            color: #666;
            font-size: 14px;
        }
        .helper-text {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 8px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>DevTools Element Screenshot Challenge</h1>
        
        <div class="instruction">
            <h3>📋 Your Task:</h3>
            <ol>
                <li>Open Chrome DevTools (press <kbd>F12</kbd> or <kbd>Ctrl+Shift+I</kbd>)</li>
                <li>Use the element picker to inspect the purple card below (or navigate the DOM tree)</li>
                <li>Right-click on the <code>&lt;div id="target-card"&gt;</code> element in the Elements panel</li>
                <li>Select <strong>"Capture node screenshot"</strong> from the context menu</li>
                <li>The screenshot will automatically download to your Downloads folder</li>
            </ol>
        </div>

        <div id="target-card">
            <h2>🎯 Target Element</h2>
            <p>This is the element you need to screenshot. Use DevTools to inspect this specific DOM node and capture only this card - not the entire page!</p>
            <p style="margin-top: 15px; font-size: 14px; opacity: 0.8;">ID: <code style="background: rgba(255,255,255,0.2); padding: 2px 6px; border-radius: 3px;">target-card</code></p>
        </div>

        <div class="helper-text">
            <strong>💡 Tip:</strong> Make sure you're right-clicking on the element in the DevTools <em>Elements panel</em>, 
            not on the page itself. The "Capture node screenshot" option is only available in the DevTools context menu.
        </div>

        <div class="footer">
            <p>This text should <strong>NOT</strong> appear in your element screenshot.</p>
            <p>Element dimensions: approximately 450px × 180px</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/element_screenshot_test.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/element_screenshot_test.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/element_screenshot_test.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/element_screenshot_test.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Verify we're on the correct page
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$CURRENT_URL" == *"element_screenshot_test.html"* ]]; then
        echo "✓ Correct page loaded: $CURRENT_URL"
    else
        echo "⚠ Warning: Unexpected URL: $CURRENT_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the element screenshot test page"
echo "Agent should now:"
echo "  1. Open DevTools (F12 or Ctrl+Shift+I)"
echo "  2. Inspect the purple target card element"
echo "  3. Right-click on <div id='target-card'> in Elements panel"
echo "  4. Select 'Capture node screenshot'"
echo "  5. Screenshot will download automatically"