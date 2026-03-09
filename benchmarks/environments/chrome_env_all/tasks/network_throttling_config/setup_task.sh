#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network Throttling Configuration Task Setup ==="
echo "Task: Configure DevTools network throttling to Fast 3G"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick bc || true

# Install websocket client for CDP if needed
pip3 install -q websocket-client 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create test page with multiple resources for throttling detection
echo "Creating network test page with multiple resources..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/network_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Throttling Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 40px;
            max-width: 1200px;
            margin: 0 auto;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        h1 {
            text-align: center;
            font-size: 2.5em;
            margin-bottom: 20px;
        }
        .info {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .image-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-top: 30px;
        }
        .image-grid img {
            width: 100%;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
        }
        #status {
            text-align: center;
            font-size: 1.2em;
            margin-top: 20px;
            padding: 15px;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 8px;
        }
    </style>
</head>
<body>
    <h1>🌐 Network Throttling Test Page</h1>
    
    <div class="info">
        <h2>Purpose</h2>
        <p>This page is designed to test network throttling in Chrome DevTools. It contains multiple images and resources that will load slower when throttling is enabled.</p>
        
        <h3>Instructions:</h3>
        <ol>
            <li>Press <strong>F12</strong> or <strong>Ctrl+Shift+I</strong> to open DevTools</li>
            <li>Click on the <strong>Network</strong> tab in DevTools</li>
            <li>Find the throttling dropdown (shows "No throttling" by default)</li>
            <li>Click the dropdown and select <strong>"Fast 3G"</strong></li>
            <li>Reload the page (F5) to see the throttling effect</li>
        </ol>
    </div>

    <div id="status">Loading resources...</div>

    <div class="image-grid">
        <img src="https://via.placeholder.com/300x200/FF6B6B/FFFFFF?text=Image+1" alt="Test Image 1" onload="imageLoaded(1)">
        <img src="https://via.placeholder.com/300x200/4ECDC4/FFFFFF?text=Image+2" alt="Test Image 2" onload="imageLoaded(2)">
        <img src="https://via.placeholder.com/300x200/45B7D1/FFFFFF?text=Image+3" alt="Test Image 3" onload="imageLoaded(3)">
        <img src="https://via.placeholder.com/300x200/FFA07A/FFFFFF?text=Image+4" alt="Test Image 4" onload="imageLoaded(4)">
        <img src="https://via.placeholder.com/300x200/98D8C8/FFFFFF?text=Image+5" alt="Test Image 5" onload="imageLoaded(5)">
        <img src="https://via.placeholder.com/300x200/F7DC6F/000000?text=Image+6" alt="Test Image 6" onload="imageLoaded(6)">
    </div>

    <script>
        let loadedImages = 0;
        const totalImages = 6;
        const startTime = performance.timing.navigationStart;

        function imageLoaded(num) {
            loadedImages++;
            const currentTime = Date.now();
            const elapsed = currentTime - startTime;
            
            document.getElementById('status').innerHTML = 
                `Loaded ${loadedImages}/${totalImages} images in ${(elapsed/1000).toFixed(2)}s`;
            
            if (loadedImages === totalImages) {
                document.getElementById('status').innerHTML += ' - ✓ All resources loaded!';
                
                // Store load time in window for potential verification
                window.pageLoadTime = elapsed;
                console.log(`Total page load time: ${elapsed}ms`);
            }
        }

        // Fetch some JSON data as well
        fetch('https://jsonplaceholder.typicode.com/posts/1')
            .then(response => response.json())
            .then(data => {
                console.log('API fetch successful:', data.title);
            })
            .catch(error => console.error('API fetch failed:', error));

        // Log when DOM is ready
        document.addEventListener('DOMContentLoaded', function() {
            const domTime = Date.now() - startTime;
            console.log(`DOM ready in: ${domTime}ms`);
        });

        // Log when page is fully loaded
        window.addEventListener('load', function() {
            const loadTime = Date.now() - startTime;
            console.log(`Page fully loaded in: ${loadTime}ms`);
        });
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/network_test.html"
echo "✓ Network test page created at: $TEST_PAGE_DIR/network_test.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/network_test.html"
echo "Navigating to test page: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/network_test.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Capture baseline state (DevTools should be closed)
    TABS_INFO=$(curl -s http://localhost:9222/json 2>/dev/null || echo "[]")
    DEVTOOLS_OPEN=$(echo "$TABS_INFO" | jq '[.[] | select(.url | contains("devtools://"))] | length' 2>/dev/null || echo "0")
    echo "✓ DevTools initially closed (devtools tabs: $DEVTOOLS_OPEN)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Store initial state for verification
mkdir -p /tmp/network_throttling_verification
echo "closed" > /tmp/network_throttling_verification/initial_devtools_state.txt
date +%s%3N > /tmp/network_throttling_verification/setup_timestamp.txt

echo "=== Setup complete ==="
echo "Chrome is displaying the network test page"
echo ""
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Click on 'Network' tab"
echo "  3. Find 'No throttling' dropdown in Network panel"
echo "  4. Click dropdown and select 'Fast 3G'"
echo "  5. Optionally reload page (F5) to see throttling effect"