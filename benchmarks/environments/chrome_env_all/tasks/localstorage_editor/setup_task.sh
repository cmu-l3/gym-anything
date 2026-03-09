#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools LocalStorage Manipulation Task Setup ==="
echo "Task: Use DevTools Application panel to add localStorage entries"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip python3-requests || true

# Install websocket client for CDP communication if needed
pip3 install -q websocket-client 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page with some initial content
echo "Creating localStorage test page..."
TEST_PAGE_DIR="/tmp/localstorage_test"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>LocalStorage Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        h1 {
            margin-top: 0;
            text-align: center;
        }
        .instruction {
            background: rgba(255, 255, 255, 0.2);
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .code {
            background: rgba(0, 0, 0, 0.3);
            padding: 10px;
            border-radius: 5px;
            font-family: monospace;
            margin: 10px 0;
        }
        #status {
            margin-top: 20px;
            padding: 15px;
            border-radius: 5px;
            background: rgba(255, 255, 255, 0.2);
            min-height: 100px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 DevTools LocalStorage Task</h1>
        
        <div class="instruction">
            <h2>Your Task:</h2>
            <p>Use Chrome DevTools to add the following localStorage entries:</p>
            <div class="code">
                <strong>Key:</strong> user_preference<br>
                <strong>Value:</strong> dark_mode
            </div>
            <div class="code">
                <strong>Key:</strong> session_count<br>
                <strong>Value:</strong> 5
            </div>
        </div>

        <div class="instruction">
            <h3>Steps:</h3>
            <ol>
                <li>Press <strong>F12</strong> to open DevTools</li>
                <li>Click on the <strong>Application</strong> tab</li>
                <li>In the sidebar, expand <strong>Local Storage</strong></li>
                <li>Click on <strong>http://localhost:8000</strong></li>
                <li>Add the two key-value pairs as specified above</li>
            </ol>
        </div>

        <div id="status">
            <h3>Current LocalStorage Contents:</h3>
            <div id="storage-display" style="font-family: monospace;">
                Loading...
            </div>
        </div>
    </div>

    <script>
        // Display current localStorage contents
        function updateDisplay() {
            const display = document.getElementById('storage-display');
            const items = [];
            
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                const value = localStorage.getItem(key);
                items.push(`${key}: ${value}`);
            }
            
            if (items.length === 0) {
                display.textContent = '(empty)';
            } else {
                display.innerHTML = items.map(item => `<div>• ${item}</div>`).join('');
            }
        }

        // Update display every second
        updateDisplay();
        setInterval(updateDisplay, 1000);

        // Log to console for debugging
        console.log('LocalStorage Test Page loaded');
        console.log('Current localStorage:', localStorage);
    </script>
</body>
</html>
EOF

chown -R ga:ga "$TEST_PAGE_DIR"
echo "✓ Test page created at: $TEST_PAGE_DIR/index.html"

# Start HTTP server for the test page
echo "Starting HTTP server on port 8000..."
cd "$TEST_PAGE_DIR"
su - ga -c "cd $TEST_PAGE_DIR && python3 -m http.server 8000 </dev/null >/dev/null 2>&1 &"
SERVER_PID=$!
echo $SERVER_PID > /tmp/localstorage_server.pid
sleep 2

# Verify server is running
if curl -s http://localhost:8000/ > /dev/null 2>&1; then
    echo "✓ HTTP server is running on port 8000"
else
    echo "⚠ Warning: HTTP server may not be running correctly"
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh http://localhost:8000/" &
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
TEST_URL="http://localhost:8000/"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://localhost:8000/'" || true
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

echo "=== Setup complete ==="
echo "Chrome should be displaying the LocalStorage test page"
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Navigate to Application tab"
echo "  3. Expand Local Storage → http://localhost:8000"
echo "  4. Add entries: user_preference=dark_mode, session_count=5"