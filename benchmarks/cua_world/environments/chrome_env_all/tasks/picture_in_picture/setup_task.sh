#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Picture-in-Picture Task Setup ==="
echo "Task: Activate Picture-in-Picture mode for a video"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 || true

# Wait for environment to be ready
sleep 2

# Create test video page with embedded video
echo "Creating test video page..."
VIDEO_PAGE="/tmp/pip_test_video.html"
cat > "$VIDEO_PAGE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Picture-in-Picture Test - Video Player</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 50px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .instructions {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
            border-left: 4px solid #2196f3;
        }
        video {
            width: 100%;
            max-width: 640px;
            height: auto;
            border: 2px solid #ddd;
            border-radius: 4px;
            display: block;
            margin: 20px auto;
        }
        .info {
            color: #666;
            font-size: 14px;
            text-align: center;
            margin-top: 20px;
        }
        #status {
            padding: 10px;
            margin-top: 20px;
            border-radius: 4px;
            text-align: center;
            font-weight: bold;
        }
        .status-inactive {
            background: #fff3cd;
            color: #856404;
        }
        .status-active {
            background: #d4edda;
            color: #155724;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎬 Picture-in-Picture Test</h1>
        
        <div class="instructions">
            <strong>Instructions:</strong> Right-click on the video below and select "Picture in Picture" from the context menu to activate floating video mode.
        </div>
        
        <video id="testVideo" controls autoplay muted loop>
            <source src="https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4" type="video/mp4">
            <source src="https://www.w3schools.com/html/mov_bbb.mp4" type="video/mp4">
            Your browser does not support the video tag.
        </video>
        
        <div id="status" class="status-inactive">
            Picture-in-Picture: Inactive
        </div>
        
        <div class="info">
            <p>This video will automatically play (muted) for testing purposes.</p>
            <p>Video source: Big Buck Bunny (public domain)</p>
        </div>
    </div>
    
    <script>
        const video = document.getElementById('testVideo');
        const statusDiv = document.getElementById('status');
        
        // Ensure video plays (required for PiP)
        video.play().catch(err => {
            console.warn('Autoplay prevented:', err);
        });
        
        // Monitor PiP state changes
        video.addEventListener('enterpictureinpicture', () => {
            console.log('✓ Entered Picture-in-Picture mode');
            statusDiv.textContent = 'Picture-in-Picture: ACTIVE ✓';
            statusDiv.className = 'status-active';
            
            // Store PiP state in window for debugging
            window.pipActive = true;
        });
        
        video.addEventListener('leavepictureinpicture', () => {
            console.log('✗ Left Picture-in-Picture mode');
            statusDiv.textContent = 'Picture-in-Picture: Inactive';
            statusDiv.className = 'status-inactive';
            
            window.pipActive = false;
        });
        
        // Log video state for debugging
        video.addEventListener('loadeddata', () => {
            console.log('Video loaded successfully');
        });
        
        video.addEventListener('error', (e) => {
            console.error('Video error:', e);
            statusDiv.textContent = 'Video Error - Please reload';
            statusDiv.style.background = '#f8d7da';
            statusDiv.style.color = '#721c24';
        });
        
        // Helper function to check PiP state (accessible from console/CDP)
        window.isPiPActive = function() {
            return document.pictureInPictureElement !== null;
        };
        
        // Log current state every few seconds for debugging
        setInterval(() => {
            const isPiP = window.isPiPActive();
            console.log('PiP status check:', isPiP ? 'ACTIVE' : 'inactive');
        }, 5000);
    </script>
</body>
</html>
EOF

chown ga:ga "$VIDEO_PAGE" 2>/dev/null || true
echo "✓ Test video page created at: $VIDEO_PAGE"

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

# Navigate to the test video page
VIDEO_URL="file://${VIDEO_PAGE}"
echo "Navigating to: $VIDEO_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$VIDEO_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true

# Wait for page and video to load
echo "Waiting for video to load..."
sleep 5

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check if video page loaded
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"pip_test_video.html"* ]]; then
        echo "✓ Video page loaded successfully"
    else
        echo "⚠ Warning: Video page may not have loaded correctly"
        echo "  Active URL: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the test video page"
echo "Agent should:"
echo "  1. Ensure video is playing"
echo "  2. Right-click on the video player"
echo "  3. Select 'Picture in Picture' from context menu"
echo "  4. Verify floating PiP window appears"