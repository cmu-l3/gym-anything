#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Audio Control Task Setup: tab_audio_mute@1 ==="
echo "Task: Manage audio playback by selectively muting tabs with media content"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create demo pages with audio/video content
echo "Creating demo HTML pages with audio content..."
DEMO_DIR="/home/ga/Documents/audio_demo"
mkdir -p "$DEMO_DIR"

# Create music page with background audio
cat > "$DEMO_DIR/background_music.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Background Music Demo - Relaxing Sounds</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        h1 { text-align: center; margin-bottom: 30px; }
        .audio-player {
            background: rgba(255, 255, 255, 0.2);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        .status { 
            text-align: center; 
            font-size: 18px; 
            margin: 20px 0;
            font-weight: bold;
        }
        .controls { text-align: center; margin: 20px 0; }
        button {
            background: #4CAF50;
            color: white;
            border: none;
            padding: 12px 30px;
            font-size: 16px;
            border-radius: 5px;
            cursor: pointer;
            margin: 5px;
        }
        button:hover { background: #45a049; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 Background Music Player</h1>
        <div class="status" id="status">Audio is playing...</div>
        <div class="audio-player">
            <audio id="audioPlayer" loop autoplay>
                <!-- Using a simple tone generated via Web Audio API as fallback -->
                <p>Your browser does not support the audio element.</p>
            </audio>
            <div class="controls">
                <button onclick="playAudio()">▶️ Play</button>
                <button onclick="pauseAudio()">⏸️ Pause</button>
            </div>
        </div>
        <p style="text-align: center; margin-top: 20px;">
            This page demonstrates background music playback.<br>
            You can mute this tab using the speaker icon on the tab title.
        </p>
    </div>

    <script>
        // Generate a simple tone using Web Audio API
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();
        
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);
        
        oscillator.frequency.value = 440; // A4 note
        oscillator.type = 'sine';
        gainNode.gain.value = 0.1; // Low volume
        
        // Start the oscillator
        oscillator.start();
        
        // Also try to play the audio element
        const audioPlayer = document.getElementById('audioPlayer');
        audioPlayer.play().catch(e => {
            console.log('Autoplay blocked:', e);
            document.getElementById('status').textContent = 'Click Play to start audio';
        });
        
        function playAudio() {
            if (audioContext.state === 'suspended') {
                audioContext.resume();
            }
            audioPlayer.play().catch(e => console.log('Play error:', e));
            document.getElementById('status').textContent = 'Audio is playing...';
        }
        
        function pauseAudio() {
            if (audioContext.state === 'running') {
                audioContext.suspend();
            }
            audioPlayer.pause();
            document.getElementById('status').textContent = 'Audio is paused';
        }
    </script>
</body>
</html>
EOF

# Create video page
cat > "$DEMO_DIR/video_content.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Video Content Demo - Educational Tutorial</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 900px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        h1 { text-align: center; margin-bottom: 30px; }
        .video-container {
            background: black;
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            text-align: center;
        }
        .status { 
            text-align: center; 
            font-size: 18px; 
            margin: 20px 0;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎬 Video Tutorial Player</h1>
        <div class="status" id="status">Video with audio is playing...</div>
        <div class="video-container">
            <video id="videoPlayer" width="640" height="360" loop autoplay muted>
                <!-- Video with audio track -->
                <p>Your browser does not support the video element.</p>
            </video>
        </div>
        <p style="text-align: center; margin-top: 20px;">
            This page demonstrates video content with audio.<br>
            You can mute this tab using the speaker icon on the tab title.
        </p>
    </div>

    <script>
        // Generate audio for the video context
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();
        
        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);
        
        oscillator.frequency.value = 523; // C5 note (different from music page)
        oscillator.type = 'square';
        gainNode.gain.value = 0.08;
        
        oscillator.start();
        
        const videoPlayer = document.getElementById('videoPlayer');
        
        // Unmute after a short delay to bypass autoplay restrictions
        setTimeout(() => {
            videoPlayer.muted = false;
            videoPlayer.play().catch(e => {
                console.log('Autoplay blocked:', e);
                document.getElementById('status').textContent = 'Click to enable audio';
            });
        }, 100);
    </script>
</body>
</html>
EOF

# Create silent article page
cat > "$DEMO_DIR/silent_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Development Best Practices - Technical Article</title>
    <style>
        body {
            font-family: 'Georgia', serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: #f5f5f5;
            color: #333;
            line-height: 1.8;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #2c3e50; 
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
            margin-bottom: 30px;
        }
        h2 { color: #34495e; margin-top: 30px; }
        p { margin: 15px 0; text-align: justify; }
        .highlight {
            background: #e8f4f8;
            padding: 15px;
            border-left: 4px solid #3498db;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📚 Web Development Best Practices</h1>
        
        <h2>Introduction</h2>
        <p>Modern web development requires a comprehensive understanding of best practices to create efficient, maintainable, and scalable applications. This article explores essential principles that every web developer should follow to ensure code quality and optimal user experience.</p>

        <h2>Code Organization</h2>
        <p>Proper code organization is fundamental to maintaining large-scale web applications. Structure your project with clear separation of concerns, using modules and components to encapsulate functionality. Follow consistent naming conventions and maintain a logical directory hierarchy that reflects your application's architecture.</p>

        <div class="highlight">
            <strong>Key Principle:</strong> Keep your codebase modular and maintainable by following SOLID principles and DRY (Don't Repeat Yourself) methodology.
        </div>

        <h2>Performance Optimization</h2>
        <p>Website performance directly impacts user experience and search engine rankings. Optimize images, minify CSS and JavaScript, leverage browser caching, and implement lazy loading for images and content below the fold. Consider using Content Delivery Networks (CDNs) to serve static assets efficiently.</p>

        <h2>Responsive Design</h2>
        <p>With the diverse range of devices accessing the web, responsive design is no longer optional. Use flexible grid layouts, media queries, and relative units to ensure your website adapts seamlessly to different screen sizes. Test thoroughly across various devices and browsers.</p>

        <h2>Accessibility Standards</h2>
        <p>Web accessibility ensures that people with disabilities can use your website effectively. Follow WCAG guidelines by providing proper semantic HTML, ARIA labels, keyboard navigation support, and sufficient color contrast. Accessibility benefits all users, not just those with disabilities.</p>

        <h2>Security Best Practices</h2>
        <p>Security should be a priority from the start of development. Implement HTTPS, sanitize user inputs, use parameterized queries to prevent SQL injection, and keep dependencies updated. Follow the principle of least privilege and implement proper authentication and authorization mechanisms.</p>

        <h2>Version Control</h2>
        <p>Use version control systems like Git to track changes, collaborate with team members, and maintain a history of your project. Follow branching strategies, write meaningful commit messages, and conduct code reviews before merging changes to the main branch.</p>

        <h2>Testing and Quality Assurance</h2>
        <p>Comprehensive testing is essential for delivering reliable software. Implement unit tests, integration tests, and end-to-end tests. Use continuous integration and continuous deployment (CI/CD) pipelines to automate testing and deployment processes.</p>

        <h2>Conclusion</h2>
        <p>Adhering to web development best practices ensures that your applications are robust, maintainable, and provide excellent user experiences. Continuously learn and adapt to new technologies and methodologies to stay current in this rapidly evolving field.</p>

        <p style="text-align: center; margin-top: 40px; color: #7f8c8d; font-size: 14px;">
            This is a silent page with no audio content.
        </p>
    </div>
</body>
</html>
EOF

chown -R ga:ga "$DEMO_DIR"
echo "✓ Demo pages created in: $DEMO_DIR"

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

# Navigate to a neutral starting page
echo "Navigating to starting page..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'about:blank'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 2

# Close any extra tabs to ensure clean start
echo "Ensuring single tab start..."
for i in {1..5}; do
    TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "1")
    if [ "$TAB_COUNT" -gt 1 ]; then
        echo "Found $TAB_COUNT tabs, closing extras..."
        su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+w" || true
        sleep 0.5
    else
        break
    fi
done

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    INITIAL_TAB_COUNT=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.type == "page")] | length' || echo "unknown")
    echo "✓ Starting with $INITIAL_TAB_COUNT tab(s)"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo ""
echo "=== Setup complete ==="
echo "Demo pages available at:"
echo "  1. Music: file:///home/ga/Documents/audio_demo/background_music.html"
echo "  2. Video: file:///home/ga/Documents/audio_demo/video_content.html"
echo "  3. Article: file:///home/ga/Documents/audio_demo/silent_article.html"
echo ""
echo "Agent should:"
echo "  1. Open three tabs with the above URLs"
echo "  2. Identify tabs with audio (music and video pages will have speaker icons)"
echo "  3. Right-click on music tab → Select 'Mute tab'"
echo "  4. Right-click on video tab → Select 'Mute tab'"
echo "  5. Leave the article tab unmuted"
echo ""