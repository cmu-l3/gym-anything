#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Snippet Creation Task Setup ==="
echo "Task: Create a JavaScript snippet in DevTools that modifies page title"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for potential IndexedDB parsing
pip3 install -q plyvel 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a simple test HTML page for snippet execution
echo "Creating test HTML page for snippet execution..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/snippet_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevTools Snippet Test Page</title>
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
            padding: 40px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        h1 {
            margin-top: 0;
            font-size: 2.5em;
        }
        .instruction {
            background: rgba(255, 255, 255, 0.2);
            padding: 20px;
            border-radius: 5px;
            margin: 20px 0;
        }
        code {
            background: rgba(0, 0, 0, 0.3);
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔧 DevTools Snippet Test Page</h1>
        
        <div class="instruction">
            <h2>Task: Create a DevTools Snippet</h2>
            <p>Your goal is to create a reusable JavaScript snippet in Chrome DevTools:</p>
            <ol>
                <li>Press <code>F12</code> to open DevTools</li>
                <li>Navigate to the <strong>Sources</strong> panel</li>
                <li>Open the <strong>Snippets</strong> pane (may need to click '>>' menu)</li>
                <li>Click <strong>+ New snippet</strong></li>
                <li>Rename it to: <code>PageTitleChanger</code></li>
                <li>Write the code:
                    <pre style="background: rgba(0,0,0,0.5); padding: 10px; border-radius: 5px; overflow-x: auto;">
document.title = 'Modified by DevTools Snippet';
console.log('Snippet executed successfully');</pre>
                </li>
                <li>Save with <code>Ctrl+S</code></li>
                <li>Execute the snippet (right-click → Run, or Ctrl+Enter)</li>
            </ol>
        </div>
        
        <div class="instruction">
            <h2>Expected Result</h2>
            <p>After running the snippet:</p>
            <ul>
                <li>The browser tab title should change to: <strong>"Modified by DevTools Snippet"</strong></li>
                <li>The Console should show: <code>Snippet executed successfully</code></li>
            </ul>
        </div>
        
        <p style="margin-top: 40px; text-align: center; opacity: 0.8;">
            Current page title: <strong id="current-title"></strong>
        </p>
    </div>
    
    <script>
        // Display current title
        document.getElementById('current-title').textContent = document.title;
        
        // Monitor title changes
        setInterval(() => {
            const titleElement = document.getElementById('current-title');
            if (titleElement.textContent !== document.title) {
                titleElement.textContent = document.title;
                titleElement.style.color = '#00ff00';
                titleElement.style.fontWeight = 'bold';
            }
        }, 500);
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/snippet_test_page.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/snippet_test_page.html"

# Ensure Chrome is properly focused and on the test page
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
TEST_PAGE_URL="file:///home/ga/Documents/snippet_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/snippet_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Capture initial page title for comparison
    INITIAL_TITLE=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].title // ""')
    echo "✓ Initial page title: $INITIAL_TITLE"
    echo "$INITIAL_TITLE" > /tmp/initial_page_title.txt
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Store initial timestamp for later verification
date +%s > /tmp/task_start_timestamp.txt

echo "=== Setup complete ==="
echo "Chrome is ready with test page loaded"
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Navigate to Sources panel → Snippets"
echo "  3. Create new snippet named 'PageTitleChanger'"
echo "  4. Write the JavaScript code to change title and log message"
echo "  5. Save (Ctrl+S) and execute the snippet"