#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools CSS Editing Task Setup: inspect_element_css_edit@1 ==="
echo "Task: Inspect element and modify CSS background color to red"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip python3-websocket python3-requests || true

# Install websocket-client for CDP verification
pip3 install -q websocket-client 2>/dev/null || true

# Wait for environment to be ready
sleep 2

echo "Creating test HTML page..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

# Create a simple test page with clearly identifiable element
cat > "$TEST_PAGE_DIR/css_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CSS Editing Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 40px;
            background-color: #f5f5f5;
        }
        #main-heading {
            background-color: lightblue;
            color: black;
            padding: 20px;
            font-size: 32px;
            border: 2px solid #333;
            margin-bottom: 20px;
            text-align: center;
        }
        .content {
            background-color: white;
            padding: 20px;
            margin-top: 20px;
            border-radius: 5px;
        }
        .instructions {
            background-color: #fff3cd;
            padding: 15px;
            margin: 20px 0;
            border-left: 4px solid #ffc107;
        }
    </style>
</head>
<body>
    <h1 id="main-heading">Welcome to CSS Editing</h1>
    
    <div class="instructions">
        <h3>Task Instructions:</h3>
        <p><strong>Right-click</strong> on the heading above and select <strong>"Inspect"</strong> to open DevTools.</p>
        <p>In the <strong>Styles</strong> pane, modify the <code>background-color</code> property to <strong>red</strong>.</p>
        <p>You can add it to <code>element.style</code> or modify the existing rule.</p>
    </div>
    
    <div class="content">
        <h2>About This Page</h2>
        <p>This is a test page for demonstrating Chrome DevTools CSS editing capabilities.</p>
        <p>The heading above currently has a light blue background. Your task is to change it to red.</p>
        <p>Acceptable red color values include:</p>
        <ul>
            <li><code>red</code> (keyword)</li>
            <li><code>#FF0000</code> (hex)</li>
            <li><code>#ff0000</code> (hex lowercase)</li>
            <li><code>rgb(255, 0, 0)</code> (rgb)</li>
            <li><code>rgb(255,0,0)</code> (rgb no spaces)</li>
        </ul>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/css_test_page.html"
echo "✓ Test HTML page created at: $TEST_PAGE_DIR/css_test_page.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/css_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/css_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check if page loaded successfully
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"css_test_page.html"* ]]; then
        echo "✓ Test page loaded successfully"
    else
        echo "⚠ Warning: Test page may not have loaded. Active URL: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the test page with the main heading."
echo "Agent should:"
echo "  1. Right-click on the 'Welcome to CSS Editing' heading"
echo "  2. Select 'Inspect' or 'Inspect Element' from the context menu"
echo "  3. In DevTools Styles pane, modify the background-color to red"
echo "  4. The verifier will check the computed style via CDP"