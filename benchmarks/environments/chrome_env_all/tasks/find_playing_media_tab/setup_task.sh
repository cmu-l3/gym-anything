#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Media-Playing Tab Detection Task Setup ==="
echo "Task: Identify and navigate to tab playing media among multiple tabs"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create HTML file with auto-playing audio
echo "Creating local HTML file with auto-playing media..."
MEDIA_DIR="/home/ga/Documents"
mkdir -p "$MEDIA_DIR"

cat > "$MEDIA_DIR/media_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Audio Player - Background Music</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            padding: 50px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-align: center;
        }
        h1 { font-size: 2.5em; margin-bottom: 20px; }
        p { font-size: 1.2em; }
        .player-info {
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 10px;
            margin-top: 30px;
        }
    </style>
</head>
<body>
    <h1>🎵 Background Music Player</h1>
    <div class="player-info">
        <p>Audio is currently playing in the background</p>
        <p style="font-size: 0.9em; margin-top: 20px;">This page demonstrates media playback detection</p>
    </div>
    
    <!-- Auto-playing audio element -->
    <audio id="audioPlayer" autoplay loop>
        <!-- Using a data URL for a simple tone generator -->
        <source id="audioSource" type="audio/wav">
    </audio>
    
    <script>
        // Generate a simple audio tone using Web Audio API
        // This ensures audio plays even without external resources
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();
        
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);
        
        oscillator.frequency.value = 440; // A4 note
        gainNode.gain.value = 0.1; // Low volume
        oscillator.type = 'sine';
        
        // Start audio on user interaction or immediately if allowed
        function startAudio() {
            try {
                oscillator.start();
                console.log('Audio started successfully');
            } catch (e) {
                console.log('Audio already started or error:', e);
            }
        }
        
        // Try to start immediately (works if autoplay is allowed)
        if (audioContext.state === 'suspended') {
            audioContext.resume().then(() => {
                startAudio();
            });
        } else {
            startAudio();
        }
        
        // Fallback: start on any user interaction
        document.addEventListener('click', () => {
            if (audioContext.state === 'suspended') {
                audioContext.resume();
            }
            startAudio();
        }, { once: true });
    </script>
</body>
</html>
EOF

chown ga:ga "$MEDIA_DIR/media_test_page.html"
echo "✓ Media test page created at: $MEDIA_DIR/media_test_page.html"

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

# Close any extra tabs to start fresh
echo "Closing extra tabs to start clean..."
for i in {1..5}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.3
    else
        break
    fi
done
sleep 1

# Open multiple background tabs with various content
echo "Opening background tabs..."

# Tab 1: Wikipedia
echo "Opening tab 1: Wikipedia"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://en.wikipedia.org/wiki/Artificial_intelligence'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 2: GitHub
echo "Opening tab 2: GitHub (new tab)"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://github.com/trending'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 3: Stack Overflow  
echo "Opening tab 3: Stack Overflow (new tab)"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://stackoverflow.com/questions'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 4: MEDIA TAB - Local HTML with auto-playing audio
echo "Opening tab 4: MEDIA TAB with audio (new tab)"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
MEDIA_URL="file:///home/ga/Documents/media_test_page.html"
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$MEDIA_URL'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Click on the page to ensure audio starts playing (autoplay may be blocked)
echo "Clicking on media page to ensure audio plays..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 400" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool click 1" || true
sleep 2

# Tab 5: Reddit (another background tab)
echo "Opening tab 5: Reddit (new tab)"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://www.reddit.com/r/programming'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Tab 6: MDN Web Docs
echo "Opening tab 6: MDN (new tab)"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+t" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 'https://developer.mozilla.org/en-US/'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Navigate to the first tab (away from media tab)
echo "Switching to first tab to hide the media tab..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+1" || true
sleep 1

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP and check tab status
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Count tabs and check for audible tab
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    AUDIBLE_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page" and .audible == true)] | length' || echo "0")
    
    echo "✓ Total tabs open: $TAB_COUNT"
    echo "✓ Tabs with audible media: $AUDIBLE_COUNT"
    
    if [ "$AUDIBLE_COUNT" -ge 1 ]; then
        echo "✓✓ Media playing tab detected successfully!"
    else
        echo "⚠ Warning: No audible media detected yet (may take a moment to register)"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome has multiple tabs open with one playing media in background"
echo "Agent should identify and navigate to the media-playing tab"
echo ""
echo "Expected agent actions:"
echo "  1. Scan tab bar for media indicator icon (speaker icon)"
echo "  2. Click on the tab showing media playback"
echo "  3. Verify it's the correct tab with playing audio"