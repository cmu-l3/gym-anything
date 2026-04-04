#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network Throttling Configuration Task Setup ==="
echo "Task: Configure DevTools Network Throttling to Slow 3G preset"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip tesseract-ocr || true

# Install Python libraries for screenshot analysis
pip3 install -q pillow pytesseract 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a test webpage with some resources for demonstrating throttling effects
echo "Creating test page with resources..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/throttling_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Throttling Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            line-height: 1.6;
        }
        h1 { color: #2c3e50; }
        .info-box {
            background: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
        .resource-list {
            list-style: none;
            padding: 0;
        }
        .resource-list li {
            padding: 10px;
            margin: 5px 0;
            background: #3498db;
            color: white;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <h1>Network Performance Testing Page</h1>
    
    <div class="info-box">
        <h2>About This Page</h2>
        <p>This page is designed to test network throttling in Chrome DevTools. 
        When throttling is enabled, you should notice significantly slower loading times.</p>
    </div>

    <div class="info-box">
        <h2>Network Throttling Instructions</h2>
        <ol>
            <li>Press <strong>F12</strong> to open Chrome DevTools</li>
            <li>Click on the <strong>Network</strong> tab</li>
            <li>Find the throttling dropdown (usually shows "No throttling")</li>
            <li>Select <strong>Slow 3G</strong> from the dropdown</li>
            <li>Reload the page (F5) to see the throttling effect</li>
        </ol>
    </div>

    <div class="info-box">
        <h2>Expected Slow 3G Settings</h2>
        <ul class="resource-list">
            <li>Download: ~400 Kbps (~50 KB/s)</li>
            <li>Upload: ~400 Kbps (~50 KB/s)</li>
            <li>Latency: 400ms (round-trip time)</li>
        </ul>
    </div>

    <div class="info-box">
        <h2>Use Cases for Network Throttling</h2>
        <p><strong>Mobile Testing:</strong> Simulate mobile network conditions for users in areas with limited connectivity.</p>
        <p><strong>Performance Testing:</strong> Identify slow-loading resources and optimize page load times.</p>
        <p><strong>Progressive Web Apps:</strong> Test offline capabilities and service worker caching.</p>
        <p><strong>User Experience:</strong> Ensure acceptable experience for users on slower connections.</p>
    </div>

    <script>
        // Add timestamp to show when page loaded
        document.addEventListener('DOMContentLoaded', function() {
            const loadTime = new Date().toLocaleTimeString();
            const timeDiv = document.createElement('div');
            timeDiv.className = 'info-box';
            timeDiv.innerHTML = '<p><strong>Page loaded at:</strong> ' + loadTime + '</p>';
            document.body.appendChild(timeDiv);
        });
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/throttling_test_page.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/throttling_test_page.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/throttling_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/throttling_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TABS=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    echo "✓ Chrome has $INITIAL_TABS tab(s) open"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the throttling test page"
echo ""
echo "Agent should now:"
echo "  1. Press F12 to open Chrome DevTools"
echo "  2. Click on 'Network' tab in DevTools"
echo "  3. Locate throttling dropdown (shows 'No throttling' by default)"
echo "  4. Select 'Slow 3G' from the dropdown menu"
echo "  5. Optionally reload page (F5) to observe throttling effect"