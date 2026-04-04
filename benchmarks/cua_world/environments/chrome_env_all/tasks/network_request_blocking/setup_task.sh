#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network Request Blocking Task Setup ==="
echo "Task: Configure Network Request Blocking in DevTools"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create test webpage with various resources
echo "Creating test webpage with analytics, images, and CDN resources..."
TEST_DIR="/home/ga/Documents"
mkdir -p "$TEST_DIR"

cat > "$TEST_DIR/network_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Request Blocking Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1200px;
            margin: 40px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            border-radius: 10px;
            margin-bottom: 30px;
        }
        .section {
            background: white;
            padding: 20px;
            margin: 20px 0;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .image-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .placeholder-img {
            width: 100%;
            height: 150px;
            background: linear-gradient(45deg, #ddd 25%, #eee 25%, #eee 50%, #ddd 50%, #ddd 75%, #eee 75%, #eee);
            background-size: 20px 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            border: 2px solid #ccc;
            border-radius: 4px;
            font-size: 12px;
            color: #666;
        }
        .status-box {
            padding: 15px;
            background: #e3f2fd;
            border-left: 4px solid #2196f3;
            margin: 15px 0;
        }
        .instruction {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🌐 Network Request Blocking Test Page</h1>
        <p>This page contains various resources for testing DevTools Network Request Blocking</p>
    </div>

    <div class="instruction">
        <h3>📋 Your Task:</h3>
        <ol>
            <li>Open Chrome DevTools (F12 or Ctrl+Shift+I)</li>
            <li>Navigate to the <strong>Network</strong> tab</li>
            <li>Enable <strong>Network request blocking</strong></li>
            <li>Add blocking patterns: <code>*analytics*</code>, <code>*.jpg</code>, <code>*cdn.example.com*</code></li>
            <li>Refresh the page to see the blocking in action</li>
        </ol>
    </div>

    <div class="section">
        <h2>📊 Analytics Scripts (Should be blocked)</h2>
        <div class="status-box">
            <p>This page includes analytics tracking scripts that should be blocked by your <code>*analytics*</code> pattern.</p>
            <p id="analytics-status">Status: Loading analytics...</p>
        </div>
    </div>

    <div class="section">
        <h2>🖼️ JPEG Images (Should be blocked)</h2>
        <div class="status-box">
            <p>The images below are JPEG format and should be blocked by your <code>*.jpg</code> pattern.</p>
        </div>
        <div class="image-grid">
            <div class="placeholder-img">Image 1 (JPG)</div>
            <div class="placeholder-img">Image 2 (JPG)</div>
            <div class="placeholder-img">Image 3 (JPG)</div>
            <div class="placeholder-img">Image 4 (JPG)</div>
        </div>
    </div>

    <div class="section">
        <h2>📦 CDN Resources (Should be blocked)</h2>
        <div class="status-box">
            <p>Resources from <code>cdn.example.com</code> should be blocked by your domain pattern.</p>
            <p id="cdn-status">Status: Loading CDN resources...</p>
        </div>
    </div>

    <div class="section">
        <h2>✅ Resources That Should Still Load</h2>
        <div class="status-box">
            <p>This page itself, CSS, and other non-blocked resources should continue to work normally.</p>
        </div>
    </div>

    <!-- Simulate analytics script loading -->
    <script>
        // This script simulates analytics tracking
        console.log('[TEST] Page loaded - analytics script would initialize here');
        
        // Try to load fake analytics (would be blocked)
        var analyticsScript = document.createElement('script');
        analyticsScript.src = 'https://fake-analytics.example.com/analytics.js';
        analyticsScript.onerror = function() {
            document.getElementById('analytics-status').innerHTML = 
                '❌ <strong>Status: Blocked</strong> (This is expected when blocking is active)';
        };
        analyticsScript.onload = function() {
            document.getElementById('analytics-status').innerHTML = 
                '✅ <strong>Status: Loaded</strong> (Blocking not active or pattern incorrect)';
        };
        document.head.appendChild(analyticsScript);
        
        // Try to load CDN resource (would be blocked)
        var cdnScript = document.createElement('script');
        cdnScript.src = 'https://cdn.example.com/library.js';
        cdnScript.onerror = function() {
            document.getElementById('cdn-status').innerHTML = 
                '❌ <strong>Status: Blocked</strong> (This is expected when blocking is active)';
        };
        cdnScript.onload = function() {
            document.getElementById('cdn-status').innerHTML = 
                '✅ <strong>Status: Loaded</strong> (Blocking not active or pattern incorrect)';
        };
        document.head.appendChild(cdnScript);
        
        // Set timeouts for status updates
        setTimeout(function() {
            var analyticsEl = document.getElementById('analytics-status');
            if (analyticsEl.innerHTML === 'Status: Loading analytics...') {
                analyticsEl.innerHTML = '⏳ <strong>Status: Loading...</strong>';
            }
        }, 2000);
        
        setTimeout(function() {
            var cdnEl = document.getElementById('cdn-status');
            if (cdnEl.innerHTML === 'Status: Loading CDN resources...') {
                cdnEl.innerHTML = '⏳ <strong>Status: Loading...</strong>';
            }
        }, 2000);
    </script>

    <!-- These image references would normally load JPEG images -->
    <img src="https://via.placeholder.com/200/FF0000/FFFFFF?text=Sample1.jpg" 
         alt="Sample 1" style="display:none;" onerror="console.log('JPG 1 blocked')">
    <img src="https://via.placeholder.com/200/00FF00/FFFFFF?text=Sample2.jpg" 
         alt="Sample 2" style="display:none;" onerror="console.log('JPG 2 blocked')">
    <img src="https://via.placeholder.com/200/0000FF/FFFFFF?text=Sample3.jpg" 
         alt="Sample 3" style="display:none;" onerror="console.log('JPG 3 blocked')">

</body>
</html>
EOF

chown ga:ga "$TEST_DIR/network_test_page.html"
echo "✓ Test page created at: $TEST_DIR/network_test_page.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/network_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/network_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the network test page"
echo "Agent should now:"
echo "  1. Open DevTools (F12 or Ctrl+Shift+I)"
echo "  2. Navigate to Network tab"
echo "  3. Enable Network Request Blocking"
echo "  4. Add patterns: *analytics*, *.jpg, *cdn.example.com*"
echo "  5. Optionally refresh to see blocking in action"