#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Media Autoplay Control Task Setup ==="
echo "Task: Block autoplay for example-news-site.com via site-specific settings"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create a sample webpage with autoplay video for context (optional)
echo "Creating sample page with autoplay video..."
SAMPLE_DIR="/home/ga/Documents"
mkdir -p "$SAMPLE_DIR"

cat > "$SAMPLE_DIR/autoplay_demo.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Autoplay Demo - Example News Site</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
        }
        .notice {
            background-color: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            margin-bottom: 20px;
            border-radius: 5px;
        }
        video {
            width: 100%;
            max-width: 640px;
            border: 2px solid #333;
        }
    </style>
</head>
<body>
    <h1>Example News Site - Video Demo</h1>
    
    <div class="notice">
        <strong>Note:</strong> This page simulates a news website with autoplay video.
        Your task is to configure Chrome to block autoplay specifically for <code>example-news-site.com</code>.
    </div>
    
    <h2>Breaking News Video</h2>
    <p>This video would normally autoplay on news websites, which can be disruptive.</p>
    
    <video controls autoplay muted>
        <source src="https://www.w3schools.com/html/mov_bbb.mp4" type="video/mp4">
        Your browser does not support the video tag.
    </video>
    
    <h2>Instructions</h2>
    <ol>
        <li>Open Chrome Settings (Menu → Settings or <code>chrome://settings</code>)</li>
        <li>Navigate to: <strong>Privacy and security → Site Settings</strong></li>
        <li>Scroll to <strong>Additional content settings</strong></li>
        <li>Click on <strong>Sound</strong> or <strong>Additional permissions</strong></li>
        <li>Under "Not allowed to play sound" or "Block", click <strong>Add</strong></li>
        <li>Enter: <code>https://example-news-site.com</code> or <code>[*.]example-news-site.com</code></li>
        <li>Click <strong>Add</strong> to save</li>
    </ol>
    
    <p><em>Target site: example-news-site.com</em></p>
</body>
</html>
EOF

chown ga:ga "$SAMPLE_DIR/autoplay_demo.html"
echo "✓ Demo page created at: $SAMPLE_DIR/autoplay_demo.html"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Navigate to the demo page as context (agent can close this and navigate to settings)
DEMO_URL="file:///home/ga/Documents/autoplay_demo.html"
echo "Navigating to demo page: $DEMO_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/autoplay_demo.html'" || true
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
    echo "✓ Current URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with autoplay demo page for context."
echo ""
echo "Agent should:"
echo "  1. Navigate to chrome://settings (Ctrl+L, type 'chrome://settings')"
echo "  2. Click 'Privacy and security' in sidebar"
echo "  3. Click 'Site Settings'"
echo "  4. Scroll to 'Additional content settings' section"
echo "  5. Click 'Sound' (or look for 'Autoplay' option)"
echo "  6. Click 'Add' button next to 'Not allowed to play sound' or 'Block'"
echo "  7. Enter: https://example-news-site.com or [*.]example-news-site.com"
echo "  8. Click 'Add' to confirm"
echo ""
echo "Target site: example-news-site.com"