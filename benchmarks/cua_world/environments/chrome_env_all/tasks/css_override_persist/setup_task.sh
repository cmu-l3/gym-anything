#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Local CSS Override Task Setup ==="
echo "Task: Enable Local Overrides and modify CSS styling persistently"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create chrome overrides directory with proper permissions
echo "Creating chrome overrides directory..."
OVERRIDE_DIR="/home/ga/chrome_overrides"
mkdir -p "$OVERRIDE_DIR"
chown ga:ga "$OVERRIDE_DIR"
chmod 755 "$OVERRIDE_DIR"
echo "✓ Override directory created: $OVERRIDE_DIR"

# Create test HTML page with styled elements
echo "Creating test HTML page..."
TEST_PAGE="/home/ga/test_css_override.html"
cat > "$TEST_PAGE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CSS Override Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        #main-heading {
            color: blue;
            font-size: 48px;
            font-weight: normal;
            text-align: center;
            margin: 50px 0;
            padding: 20px;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .instruction-box {
            background-color: #fff3cd;
            border: 2px solid #ffc107;
            border-radius: 8px;
            padding: 20px;
            margin: 20px 0;
        }
        .instruction-box h2 {
            margin-top: 0;
            color: #856404;
        }
        .instruction-box ol {
            margin: 10px 0;
            padding-left: 20px;
        }
        .instruction-box li {
            margin: 8px 0;
            line-height: 1.6;
        }
        .highlight {
            background-color: #d1ecf1;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <h1 id="main-heading">Welcome to DevTools Override Demo</h1>
    
    <div class="instruction-box">
        <h2>📝 Task Instructions</h2>
        <ol>
            <li>Open Chrome DevTools by pressing <span class="highlight">F12</span> or <span class="highlight">Ctrl+Shift+I</span></li>
            <li>Open DevTools Settings by pressing <span class="highlight">F1</span> or clicking the gear icon ⚙️</li>
            <li>Navigate to the <strong>Workspace</strong> section in Settings</li>
            <li>Under "Overrides", click <span class="highlight">Select folder</span> and choose <span class="highlight">/home/ga/chrome_overrides</span></li>
            <li>Grant DevTools permission to access the folder when prompted</li>
            <li>Close Settings and go to the <strong>Elements</strong> panel</li>
            <li>Inspect the blue heading above (or press <span class="highlight">Ctrl+Shift+C</span> and click it)</li>
            <li>In the <strong>Styles</strong> panel, find the <span class="highlight">color: blue</span> property</li>
            <li>Click on "blue" and change it to <span class="highlight">red</span></li>
            <li>The heading should turn red immediately</li>
            <li>Save the override by pressing <span class="highlight">Ctrl+S</span> in DevTools</li>
            <li>Verify the change persists by refreshing the page (<span class="highlight">F5</span>)</li>
        </ol>
    </div>
    
    <div class="instruction-box" style="background-color: #d4edda; border-color: #28a745;">
        <h2 style="color: #155724;">💡 Success Criteria</h2>
        <ul style="list-style-type: none; padding-left: 0;">
            <li>✅ Override folder configured in DevTools</li>
            <li>✅ CSS file created in override directory</li>
            <li>✅ Heading color changed from blue to red in CSS</li>
            <li>✅ Changes persist after page refresh</li>
        </ul>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE"
echo "✓ Test page created: $TEST_PAGE"

# Ensure Chrome is properly focused and on correct URL
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
TEST_PAGE_URL="file:///home/ga/test_css_override.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/test_css_override.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the test page with instructions"
echo "Agent should now:"
echo "  1. Open DevTools (F12)"
echo "  2. Configure Local Overrides (Settings > Workspace > Select folder: /home/ga/chrome_overrides)"
echo "  3. Inspect the blue heading element"
echo "  4. Change color: blue to color: red in Styles panel"
echo "  5. Save the override (Ctrl+S)"
echo "  6. Verify persistence by refreshing the page"