#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools LocalStorage Management Task Setup ==="
echo "Task: Edit localStorage via DevTools Application tab"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create test HTML page with localStorage
echo "Creating test HTML page with localStorage..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/storage_test.html" << 'EOF'
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
            margin: 40px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #4CAF50;
            padding-bottom: 10px;
        }
        .info-box {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin: 20px 0;
        }
        .storage-display {
            background: #f9f9f9;
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 15px;
            margin-top: 15px;
            font-family: monospace;
            white-space: pre-wrap;
            max-height: 300px;
            overflow-y: auto;
        }
        .instructions {
            background: #e3f2fd;
            border-left: 4px solid #2196F3;
            padding: 15px;
            margin: 20px 0;
        }
        .instructions h3 {
            margin-top: 0;
            color: #1976D2;
        }
        .instructions ol {
            margin: 10px 0;
            padding-left: 20px;
        }
        .instructions li {
            margin: 8px 0;
        }
        code {
            background: #fff3cd;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <h1>🔧 DevTools LocalStorage Management Test</h1>
    
    <div class="info-box">
        <h2>Current LocalStorage Contents</h2>
        <p>This page uses localStorage to store user preferences. The storage updates automatically every 500ms to show real-time changes.</p>
        <div class="storage-display" id="storage-display">Loading...</div>
    </div>

    <div class="instructions">
        <h3>📋 Task Instructions</h3>
        <ol>
            <li>Press <code>F12</code> or <code>Ctrl+Shift+I</code> to open DevTools</li>
            <li>Click on the <strong>Application</strong> tab in DevTools</li>
            <li>In the left sidebar, expand <strong>Storage → Local Storage</strong></li>
            <li>Click on the <code>file://</code> origin to view the key-value table</li>
            <li><strong>Edit:</strong> Change "theme" value from "light" to "dark"</li>
            <li><strong>Add:</strong> Create new entry "notifications" = "enabled"</li>
            <li><strong>Delete:</strong> Remove the "fontSize" entry</li>
            <li><strong>Preserve:</strong> Keep "username" unchanged</li>
        </ol>
    </div>

    <script>
        // Initialize localStorage with test data on first load
        function initializeStorage() {
            if (!localStorage.getItem('_initialized')) {
                localStorage.setItem('username', 'testuser');
                localStorage.setItem('theme', 'light');
                localStorage.setItem('fontSize', '14');
                localStorage.setItem('_initialized', 'true');
                console.log('✓ LocalStorage initialized with test data');
            }
        }

        // Display current localStorage contents
        function displayStorage() {
            const storage = {};
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                if (key !== '_initialized') {  // Hide internal flag
                    storage[key] = localStorage.getItem(key);
                }
            }
            
            const display = document.getElementById('storage-display');
            if (Object.keys(storage).length === 0) {
                display.textContent = '(empty)';
            } else {
                display.textContent = JSON.stringify(storage, null, 2);
            }
        }

        // Initialize on page load
        initializeStorage();
        displayStorage();

        // Update display every 500ms to show real-time changes
        setInterval(displayStorage, 500);

        // Log initial state to console for debugging
        console.log('Initial localStorage state:');
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            console.log(`  ${key}: ${localStorage.getItem(key)}`);
        }
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/storage_test.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/storage_test.html"

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
TEST_URL="file:///home/ga/Documents/storage_test.html"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/storage_test.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Verify the test page loaded
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"storage_test.html"* ]]; then
        echo "✓ Test page loaded successfully"
    else
        echo "⚠ Warning: Test page may not have loaded (current URL: $ACTIVE_URL)"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the localStorage test page"
echo "Agent should:"
echo "  1. Open DevTools (F12)"
echo "  2. Navigate to Application → Local Storage"
echo "  3. Edit 'theme' to 'dark'"
echo "  4. Add 'notifications' = 'enabled'"
echo "  5. Delete 'fontSize'"
echo "  6. Keep 'username' unchanged"