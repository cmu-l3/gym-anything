#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome JavaScript Blocking Task Setup: javascript_block_site@1 ==="
echo "Task: Block JavaScript on a specific site using Chrome's site settings"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create test page with heavy JavaScript usage
echo "Creating JavaScript test page..."
TEST_DIR="/tmp/js_block_test"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JavaScript Functionality Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 40px;
            text-align: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            margin: 0;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 10px;
            max-width: 600px;
            margin: 0 auto;
        }
        .status {
            font-size: 32px;
            font-weight: bold;
            margin: 20px 0;
            padding: 20px;
            border-radius: 5px;
        }
        .enabled { 
            background: #10b981; 
            color: white;
        }
        .disabled { 
            background: #ef4444; 
            color: white;
        }
        .counter {
            font-size: 24px;
            margin: 20px 0;
            padding: 15px;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 5px;
        }
        .features {
            margin-top: 30px;
            text-align: left;
        }
        .feature-item {
            padding: 10px;
            margin: 10px 0;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 5px;
        }
        #interactive-btn {
            padding: 15px 30px;
            font-size: 18px;
            background: #3b82f6;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            margin: 20px 0;
        }
        #interactive-btn:hover {
            background: #2563eb;
        }
        .noscript-warning {
            display: none;
            background: #ef4444;
            padding: 20px;
            border-radius: 5px;
            font-size: 20px;
        }
    </style>
</head>
<body>
    <noscript>
        <div class="noscript-warning" style="display: block;">
            ⚠️ JavaScript is BLOCKED - This page requires JavaScript to function
        </div>
    </noscript>
    
    <div class="container">
        <h1>JavaScript Test Page</h1>
        
        <div id="status" class="status disabled">
            ⚠️ JavaScript is DISABLED
        </div>
        
        <div class="counter">
            <strong>Live Counter:</strong> <span id="counter">Not Running</span>
        </div>
        
        <button id="interactive-btn" onclick="handleClick()">
            Click Me (Requires JS)
        </button>
        
        <div id="click-output" style="margin-top: 15px; font-size: 18px;"></div>
        
        <div class="features">
            <h3>JavaScript Features on This Page:</h3>
            <div class="feature-item">✓ Dynamic status indicator</div>
            <div class="feature-item">✓ Live incrementing counter</div>
            <div class="feature-item">✓ Interactive button with event handlers</div>
            <div class="feature-item">✓ Real-time DOM manipulation</div>
            <div class="feature-item">✓ Background color animation</div>
        </div>
        
        <p style="margin-top: 30px; font-size: 14px; opacity: 0.8;">
            When JavaScript is blocked, this page will show minimal functionality
        </p>
    </div>
    
    <script>
        // Update status immediately
        document.getElementById('status').textContent = '✅ JavaScript is ENABLED';
        document.getElementById('status').className = 'status enabled';
        
        // Live counter
        let count = 0;
        setInterval(() => {
            count++;
            document.getElementById('counter').textContent = count;
        }, 1000);
        
        // Button interaction
        let clickCount = 0;
        function handleClick() {
            clickCount++;
            document.getElementById('click-output').textContent = 
                `Button clicked ${clickCount} time${clickCount !== 1 ? 's' : ''}!`;
        }
        
        // Background animation
        let hue = 0;
        setInterval(() => {
            hue = (hue + 1) % 360;
            document.body.style.filter = `hue-rotate(${hue}deg)`;
        }, 50);
        
        console.log('✅ JavaScript is fully functional on this page');
        console.log('Test page loaded at:', new Date().toLocaleString());
    </script>
</body>
</html>
EOF

chown -R ga:ga "$TEST_DIR"
echo "✓ JavaScript test page created at: $TEST_DIR/index.html"

# Start HTTP server to serve the test page
echo "Starting HTTP server on port 8888..."
pkill -f "python3.*http.server.*8888" 2>/dev/null || true
sleep 1

cd "$TEST_DIR"
su - ga -c "cd $TEST_DIR && python3 -m http.server 8888 > /tmp/http_server.log 2>&1 &"
sleep 2

# Verify server is running
if curl -s http://localhost:8888/ > /dev/null 2>&1; then
    echo "✓ HTTP server is running on http://localhost:8888/"
else
    echo "⚠ Warning: HTTP server may not be responding"
fi

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh http://localhost:8888/" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
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
echo "Navigating to test page: http://localhost:8888/"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://localhost:8888/'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check current URL
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Save the target domain for verification
echo "localhost:8888" > /tmp/js_block_target_domain.txt

echo "=== Setup complete ==="
echo ""
echo "Current state:"
echo "  - Test page running at: http://localhost:8888/"
echo "  - JavaScript is currently ENABLED (status should show green)"
echo "  - Counter should be incrementing"
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://settings/content/javascript"
echo "  2. Add 'localhost:8888' to 'Not allowed to use JavaScript' list"
echo "  3. (Optional) Return to test page to verify blocking worked"
echo ""
echo "Expected result:"
echo "  - JavaScript will be blocked on localhost:8888"
echo "  - Test page will show disabled status (red)"
echo "  - Counter will not increment"