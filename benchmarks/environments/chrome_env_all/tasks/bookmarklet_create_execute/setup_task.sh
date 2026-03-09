#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarklet Creation and Execution Task Setup ==="
echo "Task: Create bookmarklet to change page background to red, then execute it"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for image analysis
pip3 install -q pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create test HTML page with white background
echo "Creating test HTML page..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/bookmarklet_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bookmarklet Test Page</title>
    <style>
        body {
            background-color: white;
            font-family: Arial, sans-serif;
            padding: 50px;
            margin: 0;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: #f9f9f9;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-top: 0;
        }
        p {
            color: #666;
            line-height: 1.6;
        }
        .instruction {
            background-color: #e3f2fd;
            padding: 15px;
            border-left: 4px solid #2196F3;
            margin: 20px 0;
        }
        .code {
            background-color: #f5f5f5;
            padding: 10px;
            border-radius: 4px;
            font-family: monospace;
            overflow-x: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Bookmarklet Test Page</h1>
        
        <p>This is a simple test page with a white background. Your task is to create a bookmarklet that will change this page's background color to bright red (#FF0000).</p>
        
        <div class="instruction">
            <strong>Instructions:</strong>
            <ol>
                <li>Open Chrome's bookmark manager (Ctrl+Shift+O)</li>
                <li>Add a new bookmark</li>
                <li>Name it "Red Background" (or similar)</li>
                <li>Set the URL to the JavaScript code provided</li>
                <li>Save the bookmarklet</li>
                <li>Click the bookmarklet to execute it</li>
            </ol>
        </div>
        
        <p><strong>Expected JavaScript code:</strong></p>
        <div class="code">
            javascript:(function(){document.body.style.backgroundColor='#FF0000';})();
        </div>
        
        <p>When you click the bookmarklet, this entire page's background should turn bright red!</p>
        
        <div style="margin-top: 40px; padding: 20px; background-color: white; border-radius: 4px;">
            <h2>What are Bookmarklets?</h2>
            <p>Bookmarklets are small JavaScript programs stored as bookmarks. When clicked, they execute code that can modify the current webpage, extract information, or perform various actions. They're powerful tools for web productivity and automation.</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/bookmarklet_test.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/bookmarklet_test.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/bookmarklet_test.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/bookmarklet_test.html'" || true
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

# Ensure bookmarks bar is visible (helps with bookmarklet access)
echo "Ensuring bookmarks bar visibility..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+b" || true
sleep 1

echo "=== Setup complete ==="
echo "Chrome should be displaying the bookmarklet test page"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+Shift+O to open bookmark manager"
echo "  2. Click 'Add new bookmark' (three-dot menu or organize button)"
echo "  3. Enter name: 'Red Background'"
echo "  4. Enter URL: javascript:(function(){document.body.style.backgroundColor='#FF0000';})();"
echo "  5. Save the bookmark"
echo "  6. Click the bookmark to execute it"
echo "  7. Verify the page background turns red"