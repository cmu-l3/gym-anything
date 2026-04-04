#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Webpage Screenshot Task Setup ==="
echo "Task: Capture a screenshot of a webpage using Chrome DevTools"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for image verification
pip3 install -q Pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a visually rich test webpage for screenshot
echo "Creating test webpage with distinctive content..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/screenshot_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Screenshot Test Page - Browser Documentation Task</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            max-width: 900px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
            margin-bottom: 30px;
        }
        .card {
            background: rgba(255, 255, 255, 0.2);
            padding: 20px;
            margin: 15px 0;
            border-radius: 10px;
            border-left: 4px solid #ffd700;
        }
        .highlight {
            background: rgba(255, 215, 0, 0.3);
            padding: 2px 8px;
            border-radius: 3px;
            font-weight: bold;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 15px;
            margin: 20px 0;
        }
        .grid-item {
            background: rgba(255, 255, 255, 0.15);
            padding: 15px;
            text-align: center;
            border-radius: 8px;
            transition: transform 0.2s;
        }
        .grid-item:hover {
            transform: scale(1.05);
        }
        .footer {
            margin-top: 30px;
            text-align: center;
            opacity: 0.7;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Browser Screenshot Documentation</h1>
        <div class="subtitle">Learning to Capture Web Content Efficiently</div>
        
        <div class="card">
            <h2>Why Take Screenshots?</h2>
            <p>Screenshots are essential for <span class="highlight">documentation</span>, <span class="highlight">bug reporting</span>, and <span class="highlight">collaboration</span>. They provide visual evidence and context that text alone cannot convey.</p>
        </div>
        
        <div class="card">
            <h2>Common Use Cases</h2>
            <ul>
                <li>Capturing error messages for technical support</li>
                <li>Creating tutorials and guides</li>
                <li>Preserving important information</li>
                <li>Sharing visual discoveries with colleagues</li>
                <li>Recording evidence of online transactions</li>
            </ul>
        </div>
        
        <div class="grid">
            <div class="grid-item">
                <h3>📸</h3>
                <p>Quick Capture</p>
            </div>
            <div class="grid-item">
                <h3>💾</h3>
                <p>Auto-Save</p>
            </div>
            <div class="grid-item">
                <h3>🎨</h3>
                <p>High Quality</p>
            </div>
            <div class="grid-item">
                <h3>⚡</h3>
                <p>Fast Access</p>
            </div>
            <div class="grid-item">
                <h3>🔍</h3>
                <p>Precise</p>
            </div>
            <div class="grid-item">
                <h3>✨</h3>
                <p>Professional</p>
            </div>
        </div>
        
        <div class="card">
            <h2>Pro Tip</h2>
            <p>Modern browsers include built-in screenshot tools accessible through Developer Tools. Press <span class="highlight">F12</span> or <span class="highlight">Ctrl+Shift+I</span> to open DevTools, then use the command palette (<span class="highlight">Ctrl+Shift+P</span>) and search for "screenshot".</p>
        </div>
        
        <div class="footer">
            This page demonstrates visually distinctive content ideal for screenshot testing
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/screenshot_test_page.html"
echo "✓ Test webpage created at: $TEST_PAGE_DIR/screenshot_test_page.html"

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
TEST_PAGE_URL="file:///home/ga/Documents/screenshot_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/screenshot_test_page.html'" || true
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

# Clear any existing screenshots from Downloads to avoid confusion
echo "Cleaning previous screenshots from Downloads..."
rm -f /home/ga/Downloads/Screenshot*.png 2>/dev/null || true
rm -f /home/ga/Downloads/screenshot*.png 2>/dev/null || true

# Record task start time for verifier
date +%s > /tmp/screenshot_task_start_time.txt
echo "✓ Task start time recorded"

echo "=== Setup complete ==="
echo "Chrome is displaying the test webpage"
echo ""
echo "Agent should now:"
echo "  1. Press F12 or Ctrl+Shift+I to open DevTools"
echo "  2. Press Ctrl+Shift+P to open Command Menu"
echo "  3. Type 'screenshot' to filter commands"
echo "  4. Select 'Capture screenshot' (for visible viewport)"
echo "  5. Screenshot will auto-save to ~/Downloads/"