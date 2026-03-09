#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Audio Muting Task Setup: mute_noisy_tab@1 ==="
echo "Task: Locate and mute a tab playing audio among multiple tabs"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create audio test page
echo "Creating test audio page..."
AUDIO_DIR="/home/ga/Documents"
mkdir -p "$AUDIO_DIR"

cat > "$AUDIO_DIR/audio_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Audio Test Page - Background Music</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 30px;
            backdrop-filter: blur(10px);
        }
        h1 { margin-top: 0; }
        .audio-info {
            background: rgba(0, 0, 0, 0.2);
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔊 Audio Test Page</h1>
        <div class="audio-info">
            <p><strong>Status:</strong> Audio is playing (silent for testing)</p>
            <p><strong>Purpose:</strong> This page demonstrates audio playback in background tabs</p>
            <p><strong>Note:</strong> You should see a speaker icon on this tab</p>
        </div>
        <p>This page is playing audio in the background. In a real scenario, this might be an advertisement, auto-playing video, or notification sound that interrupts your work.</p>
        <p>To mute this tab: Right-click on the tab with the speaker icon and select "Mute site" or "Mute tab".</p>
        
        <audio id="testAudio" autoplay loop>
            <source src="data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=" type="audio/wav">
        </audio>
        
        <script>
            // Ensure audio plays (browsers may block autoplay)
            document.addEventListener('DOMContentLoaded', function() {
                var audio = document.getElementById('testAudio');
                // Generate a simple tone programmatically
                var AudioContext = window.AudioContext || window.webkitAudioContext;
                if (AudioContext) {
                    var audioCtx = new AudioContext();
                    var oscillator = audioCtx.createOscillator();
                    var gainNode = audioCtx.createGain();
                    
                    oscillator.connect(gainNode);
                    gainNode.connect(audioCtx.destination);
                    
                    oscillator.frequency.value = 440; // A4 note
                    gainNode.gain.value = 0.01; // Very low volume
                    
                    oscillator.start();
                    
                    // Keep it playing
                    setTimeout(function() {
                        console.log('Audio context running');
                    }, 100);
                }
            });
        </script>
    </div>
</body>
</html>
EOF

chown ga:ga "$AUDIO_DIR/audio_test.html"
echo "✓ Audio test page created at: $AUDIO_DIR/audio_test.html"

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

# Function to open URL in new tab
open_tab() {
    local url="$1"
    echo "  Opening tab: $url"
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
    sleep 0.8
    su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$url'" || true
    sleep 0.3
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
    sleep 1.5
}

# Navigate to starting URL
echo "Setting up initial tab..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Open several normal tabs
echo "Opening multiple tabs..."
open_tab "https://en.wikipedia.org/wiki/Google_Chrome"
open_tab "https://developer.mozilla.org/en-US/"
open_tab "file:///home/ga/Documents/audio_test.html"
open_tab "https://github.com/trending"
open_tab "https://news.ycombinator.com"

# Switch back to an earlier tab so audio tab is in background
echo "Switching to non-audio tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Verify Chrome is ready via CDP and capture initial state
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Save initial tab state
    curl -s http://localhost:9222/json | jq '[.[] | select(.type == "page")]' > /tmp/initial_tabs.json
    INITIAL_TAB_COUNT=$(jq 'length' /tmp/initial_tabs.json)
    echo "✓ Initial state: $INITIAL_TAB_COUNT tabs open"
    
    # Record the audio tab URL
    echo "file:///home/ga/Documents/audio_test.html" > /tmp/audio_tab_url.txt
    
    # List all tab URLs for debugging
    echo "Current tabs:"
    jq -r '.[] | .url' /tmp/initial_tabs.json | head -10
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

echo "=== Setup complete ==="
echo "Chrome has multiple tabs open, one playing audio (file:///home/ga/Documents/audio_test.html)"
echo "Agent task: Locate the tab with audio (speaker icon) and mute it without closing it"
echo "Expected action: Right-click on the audio tab → Select 'Mute site' or 'Mute tab'"