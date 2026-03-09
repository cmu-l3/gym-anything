#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site Security Verification Task Setup ==="
echo "Task: Verify website security by examining HTTPS connection and certificate"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for screenshot analysis (optional)
pip3 install -q pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a simple HTML instruction page to guide the task
echo "Creating task instruction page..."
TASK_DIR="/home/ga/Documents"
mkdir -p "$TASK_DIR"

cat > "$TASK_DIR/security_check_instructions.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Verification Task Instructions</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .task-box {
            background: white;
            border-radius: 8px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #1a73e8;
            margin-top: 0;
        }
        .instruction {
            background: #e8f0fe;
            border-left: 4px solid #1a73e8;
            padding: 15px;
            margin: 20px 0;
        }
        .target-url {
            font-family: monospace;
            background: #f0f0f0;
            padding: 10px;
            border-radius: 4px;
            font-size: 16px;
            color: #0066cc;
        }
        .step {
            margin: 15px 0;
            padding-left: 25px;
        }
        .important {
            color: #d93025;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="task-box">
        <h1>🔒 Website Security Verification Task</h1>
        
        <div class="instruction">
            <p><strong>Your Mission:</strong> Navigate to a secure website and verify its security credentials before proceeding.</p>
        </div>

        <h2>Target Website:</h2>
        <div class="target-url">
            https://example.com
        </div>

        <h2>Steps to Complete:</h2>
        <div class="step">
            <strong>1.</strong> Navigate to the target URL above using the address bar (Ctrl+L)
        </div>
        <div class="step">
            <strong>2.</strong> Wait for the page to fully load
        </div>
        <div class="step">
            <strong>3.</strong> Look for the 🔒 padlock icon in the address bar (left side)
        </div>
        <div class="step">
            <strong>4.</strong> Click on the padlock icon to open the site information panel
        </div>
        <div class="step">
            <strong>5.</strong> Verify the message says "Connection is secure" or similar
        </div>
        <div class="step">
            <strong>6.</strong> (Optional) Click "Certificate" to view detailed certificate information
        </div>

        <div class="instruction">
            <p class="important">⚠️ Important:</p>
            <p>Only proceed with entering sensitive information on sites that show the secure padlock icon and valid HTTPS connection.</p>
        </div>

        <h2>What to Look For:</h2>
        <ul>
            <li>🔒 Padlock icon (indicates HTTPS encryption)</li>
            <li>Green or neutral security indicator (not red warning)</li>
            <li>"Connection is secure" message in site information panel</li>
            <li>Valid SSL/TLS certificate from trusted authority</li>
            <li>Correct domain name in certificate</li>
        </ul>
    </div>
</body>
</html>
EOF

chown ga:ga "$TASK_DIR/security_check_instructions.html"
echo "✓ Task instructions created at: $TASK_DIR/security_check_instructions.html"

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

# Navigate to the instruction page
INSTRUCTION_URL="file:///home/ga/Documents/security_check_instructions.html"
echo "Navigating to: $INSTRUCTION_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/security_check_instructions.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Chrome ready with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Record start time for verification
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="
echo "Chrome is displaying task instructions"
echo "Agent should:"
echo "  1. Navigate to https://example.com"
echo "  2. Click the padlock icon in address bar"
echo "  3. Verify 'Connection is secure' message"
echo "  4. Optionally view certificate details"