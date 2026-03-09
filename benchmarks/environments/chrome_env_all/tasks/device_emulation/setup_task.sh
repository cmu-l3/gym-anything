#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Device Emulation Task Setup ==="
echo "Task: Open DevTools and enable iPhone 12 Pro device emulation"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for image processing
pip3 install -q pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a responsive test HTML page
echo "Creating responsive test page..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/responsive_demo.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Responsive Design Demo</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Arial, sans-serif;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            padding: 30px 0;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            margin-bottom: 30px;
        }
        h1 { font-size: 2.5rem; margin-bottom: 10px; }
        .viewport-info {
            font-size: 1.2rem;
            font-weight: bold;
            margin-top: 15px;
            padding: 15px;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 5px;
            font-family: 'Courier New', monospace;
        }
        .device-indicator {
            margin-top: 20px;
            padding: 20px;
            background: rgba(255, 255, 255, 0.15);
            border-radius: 8px;
            font-size: 1.1rem;
        }
        .desktop-view {
            display: block;
            background: #4CAF50;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
        .mobile-view {
            display: none;
            background: #FF5722;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
        .feature-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 30px;
        }
        .feature-card {
            background: rgba(255, 255, 255, 0.1);
            padding: 25px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        .feature-card h3 {
            margin-bottom: 10px;
            font-size: 1.3rem;
        }
        
        /* Mobile styles */
        @media (max-width: 768px) {
            h1 { font-size: 1.8rem; }
            .viewport-info { font-size: 1rem; }
            .desktop-view { display: none; }
            .mobile-view { display: block; }
            .feature-grid {
                grid-template-columns: 1fr;
                gap: 15px;
            }
            body { padding: 15px; }
        }
        
        @media (max-width: 480px) {
            h1 { font-size: 1.5rem; }
            .viewport-info { font-size: 0.9rem; padding: 10px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎨 Responsive Design Tester</h1>
            <p>Resize your browser or use device emulation to see the layout adapt</p>
            <div class="viewport-info">
                <div>Viewport: <span id="width">---</span> × <span id="height">---</span> pixels</div>
                <div>Device Pixel Ratio: <span id="dpr">---</span></div>
            </div>
        </div>

        <div class="desktop-view">
            <h2>🖥️ Desktop View Active</h2>
            <p>You are viewing this page in desktop mode with a wide viewport.</p>
            <p>Enable device emulation in Chrome DevTools to see the mobile layout!</p>
        </div>

        <div class="mobile-view">
            <h2>📱 Mobile View Active</h2>
            <p>Perfect! You're viewing the mobile-optimized layout.</p>
            <p>This layout is designed for smaller screens and touch interfaces.</p>
        </div>

        <div class="device-indicator">
            <strong>Current Device Profile:</strong>
            <div id="device-type" style="margin-top: 10px; font-size: 1.3rem;">Detecting...</div>
        </div>

        <div class="feature-grid">
            <div class="feature-card">
                <h3>📐 Viewport Detection</h3>
                <p>The page dynamically detects viewport dimensions and adjusts the layout accordingly.</p>
            </div>
            <div class="feature-card">
                <h3>🎯 Breakpoints</h3>
                <p>CSS media queries trigger at 768px and 480px to optimize for different screen sizes.</p>
            </div>
            <div class="feature-card">
                <h3>✨ Fluid Design</h3>
                <p>All elements scale and reflow smoothly as the viewport changes.</p>
            </div>
        </div>
    </div>

    <script>
        function updateViewportInfo() {
            const width = window.innerWidth;
            const height = window.innerHeight;
            const dpr = window.devicePixelRatio || 1;
            
            document.getElementById('width').textContent = width;
            document.getElementById('height').textContent = height;
            document.getElementById('dpr').textContent = dpr.toFixed(2);
            
            let deviceType = 'Desktop';
            if (width <= 480) {
                deviceType = '📱 Small Mobile Phone';
            } else if (width <= 768) {
                deviceType = '📱 Mobile/Tablet';
            } else if (width <= 1024) {
                deviceType = '💻 Tablet/Small Laptop';
            } else {
                deviceType = '🖥️ Desktop/Laptop';
            }
            
            // Check if iPhone 12 Pro dimensions
            if (width === 390 && (height === 844 || height >= 800 && height <= 900)) {
                deviceType = '📱 iPhone 12 Pro (390×844)';
            }
            
            document.getElementById('device-type').textContent = deviceType;
        }
        
        updateViewportInfo();
        window.addEventListener('resize', updateViewportInfo);
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/responsive_demo.html"
echo "✓ Responsive demo page created at: $TEST_PAGE_DIR/responsive_demo.html"

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

# Navigate to the responsive test page
TEST_PAGE_URL="file:///home/ga/Documents/responsive_demo.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_PAGE_URL'" || true
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
echo "Chrome is displaying the responsive test page"
echo "Agent should now:"
echo "  1. Press F12 (or Ctrl+Shift+I) to open Chrome DevTools"
echo "  2. Press Ctrl+Shift+M (or click Toggle Device Toolbar button)"
echo "  3. Select 'iPhone 12 Pro' from the device dropdown"
echo "  4. Verify viewport shows 390 × 844 pixels"