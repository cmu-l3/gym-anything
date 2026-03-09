#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome localStorage DevTools Manipulation Task Setup ==="
echo "Task: Use DevTools to add localStorage entries via Application panel"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip python3-requests || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page
echo "Creating test HTML page for localStorage manipulation..."
TEST_DIR="/tmp/localstorage_test"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/test_storage.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>localStorage DevTools Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            line-height: 1.6;
        }
        h1 {
            color: #2c3e50;
        }
        .instructions {
            background: #f8f9fa;
            border-left: 4px solid #007bff;
            padding: 15px;
            margin: 20px 0;
        }
        .instructions code {
            background: #e9ecef;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
        }
        .status {
            margin-top: 30px;
            padding: 15px;
            border: 1px solid #dee2e6;
            border-radius: 5px;
            background: #fff;
        }
        .status h3 {
            margin-top: 0;
            color: #495057;
        }
        #current-storage {
            font-family: monospace;
            white-space: pre-wrap;
            background: #f8f9fa;
            padding: 10px;
            border-radius: 3px;
            min-height: 50px;
        }
        .empty {
            color: #6c757d;
            font-style: italic;
        }
    </style>
</head>
<body>
    <h1>Chrome DevTools localStorage Task</h1>
    
    <div class="instructions">
        <h2>Instructions:</h2>
        <ol>
            <li>Open Chrome DevTools by pressing <code>F12</code> or <code>Ctrl+Shift+I</code></li>
            <li>Navigate to the <strong>Application</strong> tab in DevTools</li>
            <li>In the left sidebar, expand <strong>Storage</strong> → <strong>Local Storage</strong></li>
            <li>Click on <code>http://localhost:8765</code> to view localStorage for this origin</li>
            <li>Add the following entries using the DevTools interface:
                <ul>
                    <li>Key: <code>userPreference</code>, Value: <code>darkMode</code></li>
                    <li>Key: <code>sessionToken</code>, Value: <code>abc123xyz789</code></li>
                </ul>
            </li>
        </ol>
        <p><strong>Tip:</strong> Double-click in the empty row at the bottom of the table to add new entries, or right-click and select "Add new item".</p>
    </div>
    
    <div class="status">
        <h3>Current localStorage Contents:</h3>
        <div id="current-storage" class="empty">localStorage is empty</div>
    </div>
    
    <script>
        // Display current localStorage contents in real-time
        function displayStorage() {
            const storageDiv = document.getElementById('current-storage');
            
            if (localStorage.length === 0) {
                storageDiv.className = 'empty';
                storageDiv.textContent = 'localStorage is empty';
                return;
            }
            
            storageDiv.className = '';
            const entries = {};
            
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                entries[key] = localStorage.getItem(key);
            }
            
            storageDiv.textContent = JSON.stringify(entries, null, 2);
        }
        
        // Update display every 500ms to show real-time changes
        setInterval(displayStorage, 500);
        displayStorage();
        
        // Listen for storage events (changes from DevTools)
        window.addEventListener('storage', displayStorage);
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_DIR/test_storage.html"
echo "✓ Test HTML created at: $TEST_DIR/test_storage.html"

# Start Python HTTP server on a specific port
echo "Starting HTTP server on port 8765..."
cd "$TEST_DIR"
python3 -m http.server 8765 > /tmp/http_server.log 2>&1 &
SERVER_PID=$!
echo $SERVER_PID > /tmp/http_server.pid
echo "✓ HTTP server started (PID: $SERVER_PID)"

# Wait for server to be ready
sleep 2

# Verify server is running
if curl -s http://localhost:8765/test_storage.html > /dev/null; then
    echo "✓ HTTP server is responding"
else
    echo "⚠ Warning: HTTP server not responding"
fi

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

# Navigate to the test page
TEST_URL="http://localhost:8765/test_storage.html"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://localhost:8765/test_storage.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check if our page is loaded
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"localhost:8765"* ]]; then
        echo "✓ Test page loaded successfully: $ACTIVE_URL"
    else
        echo "⚠ Warning: Test page may not be loaded (active URL: $ACTIVE_URL)"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Test page available at: $TEST_URL"
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Navigate to Application tab"
echo "  3. Expand Storage → Local Storage → http://localhost:8765"
echo "  4. Add two key-value pairs:"
echo "     - userPreference: darkMode"
echo "     - sessionToken: abc123xyz789"