#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Dark Mode Emulation Task Setup ==="
echo "Task: Enable dark mode emulation in DevTools Rendering panel"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python libraries for verification
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test page with dark mode support
echo "Creating dark mode test page..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/dark_mode_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dark Mode Emulation Test</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            background: #ffffff;
            color: #1a1a1a;
            padding: 40px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            transition: background-color 0.3s ease, color 0.3s ease;
        }
        
        .container {
            max-width: 800px;
            margin: 0 auto;
        }
        
        h1 {
            font-size: 2.5em;
            margin-bottom: 20px;
            color: #2c3e50;
        }
        
        .card {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 24px;
            margin: 20px 0;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .status {
            padding: 16px;
            background: #e7f3ff;
            border-left: 4px solid #0066cc;
            margin: 20px 0;
            border-radius: 4px;
        }
        
        .instructions {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 20px;
            border-radius: 8px;
            margin: 20px 0;
        }
        
        code {
            background: #f1f3f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }
        
        /* Dark mode styles */
        @media (prefers-color-scheme: dark) {
            body {
                background: #1a1a1a;
                color: #e0e0e0;
            }
            
            h1 {
                color: #4a9eff;
            }
            
            .card {
                background: #2d2d2d;
                border-color: #404040;
                box-shadow: 0 2px 4px rgba(0,0,0,0.3);
            }
            
            .status {
                background: #1a2332;
                border-left-color: #4a9eff;
                color: #e0e0e0;
            }
            
            .instructions {
                background: #2d2415;
                border-color: #8b7520;
                color: #f0e6d0;
            }
            
            code {
                background: #3a3a3a;
                color: #e0e0e0;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌙 Dark Mode Emulation Test</h1>
        
        <div class="status">
            <strong>Current Mode:</strong> <span id="mode-indicator">Light Mode</span>
        </div>
        
        <div class="instructions">
            <h2>Instructions for Agent:</h2>
            <ol style="margin-left: 20px; margin-top: 10px;">
                <li>Press <code>F12</code> or <code>Ctrl+Shift+I</code> to open Chrome DevTools</li>
                <li>Press <code>Ctrl+Shift+P</code> (or <code>Cmd+Shift+P</code> on Mac) to open Command Palette</li>
                <li>Type "Show Rendering" and press Enter</li>
                <li>Scroll to find "Emulate CSS media feature prefers-color-scheme"</li>
                <li>Select <code>prefers-color-scheme: dark</code> from the dropdown</li>
            </ol>
        </div>
        
        <div class="card">
            <h2>What Should Happen</h2>
            <p>When dark mode emulation is enabled, this page should:</p>
            <ul style="margin-left: 20px; margin-top: 10px;">
                <li>Change background to dark gray/black (#1a1a1a)</li>
                <li>Change text to light gray/white (#e0e0e0)</li>
                <li>Adjust all component colors to dark theme</li>
                <li>Maintain good readability and contrast</li>
            </ul>
        </div>
        
        <div class="card">
            <h2>Technical Details</h2>
            <p>This page uses the CSS media query <code>@media (prefers-color-scheme: dark)</code> to detect and respond to dark mode preferences. DevTools emulation simulates this user preference without changing your system settings.</p>
        </div>
        
        <div class="card" id="test-indicator">
            <h2>Test Indicator Card</h2>
            <p>In light mode, this card has a light gray background.</p>
            <p>In dark mode, this card has a dark gray background (#2d2d2d).</p>
        </div>
    </div>
    
    <script>
        // Update mode indicator dynamically
        function updateModeIndicator() {
            const isDarkMode = window.matchMedia('(prefers-color-scheme: dark)').matches;
            const indicator = document.getElementById('mode-indicator');
            if (isDarkMode) {
                indicator.textContent = '🌙 Dark Mode (Emulated)';
                indicator.style.fontWeight = 'bold';
                indicator.style.color = '#4a9eff';
            } else {
                indicator.textContent = '☀️ Light Mode';
                indicator.style.fontWeight = 'normal';
                indicator.style.color = 'inherit';
            }
        }
        
        // Initial update
        updateModeIndicator();
        
        // Listen for changes
        window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateModeIndicator);
    </script>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/dark_mode_test.html"
echo "✓ Dark mode test page created at: $TEST_PAGE_DIR/dark_mode_test.html"

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
TEST_URL="file:///home/ga/Documents/dark_mode_test.html"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/dark_mode_test.html'" || true
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
echo "Chrome is displaying the dark mode test page"
echo "Agent should now:"
echo "  1. Press F12 to open DevTools"
echo "  2. Press Ctrl+Shift+P to open Command Palette"
echo "  3. Type 'Show Rendering' and press Enter"
echo "  4. Find 'Emulate CSS media feature prefers-color-scheme'"
echo "  5. Select 'prefers-color-scheme: dark'"
echo "Expected: Page background should turn dark (#1a1a1a)"