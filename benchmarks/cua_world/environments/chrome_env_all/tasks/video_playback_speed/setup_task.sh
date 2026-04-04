#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Video Playback Speed Control Task Setup ==="
echo "Task: Adjust video playback speed to 1.5x"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip python3-requests || true

# Wait for environment to be ready
sleep 2

# Create a simple HTML5 video test page with controls
echo "Creating video test page..."
VIDEO_DIR="/home/ga/Documents"
mkdir -p "$VIDEO_DIR"

cat > "$VIDEO_DIR/video_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Video Playback Speed Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1000px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .instruction {
            background-color: #e8f4f8;
            border-left: 4px solid #2196F3;
            padding: 15px;
            margin: 20px 0;
        }
        .video-container {
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        video {
            width: 100%;
            max-width: 800px;
            display: block;
            margin: 0 auto;
        }
        .info {
            margin-top: 20px;
            padding: 15px;
            background-color: #fff3cd;
            border-radius: 4px;
            text-align: center;
        }
    </style>
</head>
<body>
    <h1>🎥 Video Playback Speed Control Test</h1>
    
    <div class="instruction">
        <strong>Instructions:</strong>
        <ol>
            <li>The video below has standard HTML5 controls</li>
            <li>Click the play button to start the video</li>
            <li>Right-click on the video or look for settings/gear icon</li>
            <li>Adjust playback speed to <strong>1.5x</strong></li>
            <li>Alternatively, use browser's native speed controls if available</li>
        </ol>
    </div>
    
    <div class="video-container">
        <video id="testVideo" controls>
            <source src="http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4" type="video/mp4">
            Your browser does not support HTML5 video.
        </video>
    </div>
    
    <div class="info">
        <p><strong>Current Playback Speed:</strong> <span id="speedDisplay">1.0x</span></p>
        <p><em>Goal: Set to 1.5x</em></p>
    </div>
    
    <script>
        const video = document.getElementById('testVideo');
        const speedDisplay = document.getElementById('speedDisplay');
        
        // Update speed display
        function updateSpeedDisplay() {
            speedDisplay.textContent = video.playbackRate.toFixed(2) + 'x';
        }
        
        // Listen for playback rate changes
        video.addEventListener('ratechange', updateSpeedDisplay);
        
        // Add context menu for speed control (helpful hint)
        video.addEventListener('contextmenu', function(e) {
            // Let browser handle it naturally
        });
        
        // Auto-play video after short delay
        setTimeout(function() {
            video.play().catch(function(e) {
                console.log('Auto-play prevented:', e);
            });
        }, 1000);
        
        // Update display initially
        updateSpeedDisplay();
    </script>
</body>
</html>
EOF

chown ga:ga "$VIDEO_DIR/video_test_page.html"
echo "✓ Video test page created at: $VIDEO_DIR/video_test_page.html"

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

# Navigate to the video test page
VIDEO_URL="file:///home/ga/Documents/video_test_page.html"
echo "Navigating to: $VIDEO_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/video_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Verify we're on the correct page
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"video_test_page.html"* ]]; then
        echo "✓ Video page loaded successfully"
    else
        echo "⚠ Warning: Unexpected URL: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the video test page"
echo "Agent should:"
echo "  1. Ensure video is playing"
echo "  2. Access video player settings/controls"
echo "  3. Adjust playback speed to 1.5x"
echo "  4. Common methods:"
echo "     - Right-click video → Playback speed"
echo "     - Click settings/gear icon in video controls"
echo "     - Use keyboard shortcuts (Shift+> to increase speed)"