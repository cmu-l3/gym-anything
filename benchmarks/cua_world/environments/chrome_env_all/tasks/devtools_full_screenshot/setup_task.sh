#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Full Page Screenshot Task Setup ==="
echo "Task: Use Command Palette to capture full-page screenshot"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python image processing libraries
pip3 install -q pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a test webpage with substantial scrollable content
echo "Creating test webpage with scrollable content..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/devtools_screenshot_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevTools Screenshot Test Page</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.8;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
        }
        .container {
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
        }
        h1 {
            color: #667eea;
            font-size: 2.5em;
            margin-bottom: 20px;
            text-align: center;
        }
        h2 {
            color: #764ba2;
            font-size: 1.8em;
            margin-top: 40px;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        .section {
            margin: 30px 0;
            padding: 20px;
            background: #f8f9fa;
            border-left: 5px solid #667eea;
            border-radius: 5px;
        }
        .highlight {
            background: #fff3cd;
            padding: 15px;
            margin: 20px 0;
            border-left: 5px solid #ffc107;
            border-radius: 5px;
        }
        p {
            text-align: justify;
            margin: 15px 0;
        }
        .footer {
            margin-top: 60px;
            padding-top: 20px;
            border-top: 2px solid #ddd;
            text-align: center;
            color: #666;
            font-size: 0.9em;
        }
        code {
            background: #e9ecef;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎨 Chrome DevTools Full Page Screenshot Test</h1>
        
        <div class="section">
            <h2>📸 What is a Full Page Screenshot?</h2>
            <p>A full-page screenshot captures the <strong>entire scrollable content</strong> of a webpage, not just the visible viewport. This is incredibly useful for documentation, design reviews, bug reports, and archiving complete webpage layouts.</p>
            <p>Chrome DevTools provides this functionality through its powerful Command Palette, accessible via <code>Ctrl+Shift+P</code> (or <code>Cmd+Shift+P</code> on Mac).</p>
        </div>

        <div class="highlight">
            <h2>🚀 How to Capture a Full Page Screenshot</h2>
            <p><strong>Step 1:</strong> Open DevTools by pressing <code>F12</code>, <code>Ctrl+Shift+I</code>, or right-clicking and selecting "Inspect"</p>
            <p><strong>Step 2:</strong> Open the Command Palette with <code>Ctrl+Shift+P</code></p>
            <p><strong>Step 3:</strong> Type "screenshot" to filter available commands</p>
            <p><strong>Step 4:</strong> Select "Capture full size screenshot" from the list</p>
            <p><strong>Step 5:</strong> The screenshot will be automatically saved to your Downloads folder</p>
        </div>

        <div class="section">
            <h2>🎯 Why Use the Command Palette?</h2>
            <p>The Chrome DevTools Command Palette is a productivity powerhouse that provides quick access to hundreds of commands. Beyond screenshots, you can:</p>
            <ul>
                <li>Toggle various DevTools panels and drawers</li>
                <li>Run network throttling simulations</li>
                <li>Clear browser cache and storage</li>
                <li>Switch between light and dark themes</li>
                <li>Enable/disable JavaScript</li>
                <li>Capture node-specific or area screenshots</li>
                <li>And much more!</li>
            </ul>
        </div>

        <div class="section">
            <h2>🖼️ Screenshot Types in Chrome</h2>
            <p><strong>Capture screenshot:</strong> Captures only the visible viewport area</p>
            <p><strong>Capture full size screenshot:</strong> Captures the entire scrollable page (this is what we're testing!)</p>
            <p><strong>Capture area screenshot:</strong> Allows you to select a specific rectangular region</p>
            <p><strong>Capture node screenshot:</strong> Captures a specific DOM element (requires element selection first)</p>
        </div>

        <div class="section">
            <h2>💡 Professional Use Cases</h2>
            <p><strong>Web Developers:</strong> Document page layouts, compare design iterations, create visual regression test baselines</p>
            <p><strong>QA Engineers:</strong> Capture bug reports with complete context, verify responsive designs across breakpoints</p>
            <p><strong>Designers:</strong> Review implemented designs against mockups, create style guides and pattern libraries</p>
            <p><strong>Content Managers:</strong> Archive webpage versions, create training materials and documentation</p>
        </div>

        <div class="section">
            <h2>⚙️ Technical Details</h2>
            <p>Full-page screenshots are rendered by Chrome's rendering engine, which composites all content layers including elements below the fold. The resulting image:</p>
            <ul>
                <li>Is saved as a PNG file with lossless compression</li>
                <li>Maintains the viewport width but extends to full content height</li>
                <li>Includes all CSS styling, animations (in their current state), and visible content</li>
                <li>Does not include scrollbars or browser chrome (UI elements)</li>
                <li>Typically has dimensions like 1280x3000+ pixels for content-rich pages</li>
            </ul>
        </div>

        <div class="section">
            <h2>🔍 Verification Criteria</h2>
            <p>For this task to be successfully verified, the screenshot must:</p>
            <ol>
                <li>Exist in the Downloads folder as a PNG file</li>
                <li>Have been created during the task execution timeframe</li>
                <li>Have a height greater than 1000 pixels (indicating full-page capture)</li>
                <li>Contain valid image data with realistic content variance</li>
            </ol>
        </div>

        <div class="section">
            <h2>🎓 Learning Objectives</h2>
            <p>By completing this task, you demonstrate:</p>
            <ul>
                <li>Ability to open and navigate Chrome DevTools</li>
                <li>Understanding of the Command Palette and its fuzzy search capabilities</li>
                <li>Knowledge of Chrome's built-in screenshot functionality</li>
                <li>Awareness of the difference between viewport and full-page captures</li>
                <li>Familiarity with Chrome's file download behavior</li>
            </ul>
        </div>

        <div class="section">
            <h2>📚 Additional Resources</h2>
            <p>The Command Palette was introduced in Chrome 59 and has become an essential tool for developers. It's inspired by similar quick-command interfaces in VS Code and Sublime Text.</p>
            <p>To explore more Command Palette features, open it and browse through the available commands. You'll discover many time-saving shortcuts!</p>
        </div>

        <div class="section">
            <h2>🌟 Best Practices</h2>
            <p><strong>Before capturing:</strong> Ensure the page has fully loaded, including images and dynamic content</p>
            <p><strong>Viewport width:</strong> Set your browser to a standard width (e.g., 1280px or 1920px) for consistent captures</p>
            <p><strong>File management:</strong> Screenshots are auto-named with timestamps (e.g., screenshot-2024-01-15-143022.png)</p>
            <p><strong>Performance:</strong> Very long pages (10,000+ px height) may take several seconds to render</p>
        </div>

        <div class="footer">
            <p>This page is intentionally long to test full-page screenshot functionality.</p>
            <p>If you can see this footer in your screenshot, congratulations! 🎉</p>
            <p><strong>Total page height:</strong> Approximately 2500+ pixels</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/devtools_screenshot_test.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/devtools_screenshot_test.html"

# Clear any old screenshots from Downloads folder
echo "Clearing old screenshots from Downloads..."
rm -f /home/ga/Downloads/screenshot*.png 2>/dev/null || true
rm -f /home/ga/Downloads/*.png 2>/dev/null || true
echo "✓ Downloads folder cleared"

# Record task start time for verification
date +%s > /tmp/task_start_time.txt

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
TEST_PAGE_URL="file:///home/ga/Documents/devtools_screenshot_test.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/devtools_screenshot_test.html'" || true
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
echo "Chrome is displaying the test page with scrollable content"
echo "Agent should now:"
echo "  1. Open DevTools (F12 or Ctrl+Shift+I)"
echo "  2. Open Command Palette (Ctrl+Shift+P)"
echo "  3. Type 'screenshot' to search"
echo "  4. Select 'Capture full size screenshot'"
echo "  5. Screenshot will auto-save to Downloads folder"