#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print to PDF Task Setup: print_to_pdf@1 ==="
echo "Task: Print webpage to PDF with minimal margins, no headers/footers, background graphics enabled"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install Python PDF libraries
pip3 install -q PyPDF2 pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Clear any existing PDF file to ensure clean test
rm -f /home/ga/Downloads/webpage_archive.pdf || true

# Create a test HTML file with styled content and backgrounds for verification
cat > /tmp/test_page.html <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Web Page Archive Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .header {
            background-color: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .content {
            background-color: rgba(255, 255, 255, 0.2);
            padding: 20px;
            border-radius: 10px;
            line-height: 1.6;
        }
        h1 { color: #ffd700; }
        p { margin: 10px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Web Page Archive Test</h1>
        <p>This is a test page for verifying PDF export functionality.</p>
    </div>
    <div class="content">
        <h2>Content Section</h2>
        <p>This page contains text content and background graphics that should be preserved in the PDF export.</p>
        <p>The gradient background and styled containers demonstrate the importance of background graphics in the final PDF.</p>
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        <ul>
            <li>First item with content</li>
            <li>Second item with content</li>
            <li>Third item with content</li>
        </ul>
    </div>
</body>
</html>
EOF

chown ga:ga /tmp/test_page.html

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh file:///tmp/test_page.html" &
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
echo "Navigating to: file:///tmp/test_page.html"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///tmp/test_page.html'" || true
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
echo "Chrome should be focused on test page"
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Select 'Save as PDF' destination"
echo "  3. Expand 'More settings'"
echo "  4. Set Margins to 'Minimum'"
echo "  5. Uncheck 'Headers and footers'"
echo "  6. Check 'Background graphics'"
echo "  7. Click Save and name file 'webpage_archive.pdf'"