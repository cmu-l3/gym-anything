#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Complete Webpage Save Task Setup ==="
echo "Task: Save complete webpage with all resources"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Wait for environment to be ready
sleep 2

# Create test webpage with resources
echo "Creating test webpage with resources..."
WEBROOT="/tmp/test_website"
mkdir -p "$WEBROOT/assets"

# Create CSS file
cat > "$WEBROOT/assets/style.css" << 'EOF'
body {
    font-family: 'Segoe UI', Arial, sans-serif;
    line-height: 1.6;
    max-width: 900px;
    margin: 40px auto;
    padding: 20px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: #333;
}

.container {
    background: white;
    padding: 30px;
    border-radius: 10px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.3);
}

h1 {
    color: #667eea;
    border-bottom: 3px solid #764ba2;
    padding-bottom: 10px;
}

h2 {
    color: #764ba2;
    margin-top: 25px;
}

.highlight-box {
    background: #f0f4ff;
    border-left: 4px solid #667eea;
    padding: 15px;
    margin: 20px 0;
}

.image-gallery {
    display: flex;
    gap: 15px;
    margin: 20px 0;
    flex-wrap: wrap;
}

.image-item {
    flex: 1;
    min-width: 200px;
    text-align: center;
}

.image-item img {
    max-width: 100%;
    border-radius: 8px;
    box-shadow: 0 4px 8px rgba(0,0,0,0.2);
}
EOF

# Create JavaScript file
cat > "$WEBROOT/assets/script.js" << 'EOF'
document.addEventListener('DOMContentLoaded', function() {
    console.log('Web Resources Demo Page Loaded');
    
    // Add interactive timestamp
    const timestampElement = document.getElementById('timestamp');
    if (timestampElement) {
        const now = new Date();
        timestampElement.textContent = now.toLocaleString();
    }
    
    // Add click counter
    let clickCount = 0;
    const button = document.getElementById('interactiveButton');
    if (button) {
        button.addEventListener('click', function() {
            clickCount++;
            document.getElementById('clickCounter').textContent = clickCount;
        });
    }
});
EOF

# Create test images using ImageMagick
echo "Generating test images..."
convert -size 300x200 -background "#667eea" -fill white -gravity center \
    -pointsize 30 label:"Resource\nImage 1" \
    "$WEBROOT/assets/image1.jpg" 2>/dev/null || true

convert -size 300x200 -background "#764ba2" -fill white -gravity center \
    -pointsize 30 label:"Resource\nImage 2" \
    "$WEBROOT/assets/image2.png" 2>/dev/null || true

convert -size 300x200 -background "#48bb78" -fill white -gravity center \
    -pointsize 30 label:"Resource\nImage 3" \
    "$WEBROOT/assets/image3.jpg" 2>/dev/null || true

# Create main HTML file
cat > "$WEBROOT/demo_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Resources Demo - Complete Save Test</title>
    <link rel="stylesheet" href="assets/style.css">
    <script src="assets/script.js"></script>
</head>
<body>
    <div class="container">
        <h1>Web Resources Demonstration Page</h1>
        
        <div class="highlight-box">
            <p><strong>Purpose:</strong> This page demonstrates a typical web page structure with multiple external resources including CSS stylesheets, JavaScript files, and images. It is designed to test Chrome's "Save Page As - Complete" functionality.</p>
        </div>

        <h2>About This Demo</h2>
        <p>When you save this page using Chrome's "Webpage, Complete" option, all resources (CSS, JavaScript, and images) should be downloaded into a companion folder. This ensures the page can be viewed offline with full styling and functionality preserved.</p>

        <h2>External Resources Included</h2>
        <ul>
            <li><strong>CSS Stylesheet:</strong> assets/style.css - Provides styling and layout</li>
            <li><strong>JavaScript File:</strong> assets/script.js - Adds interactivity</li>
            <li><strong>Images:</strong> Three image files demonstrating different formats (JPG, PNG)</li>
        </ul>

        <h2>Image Gallery</h2>
        <div class="image-gallery">
            <div class="image-item">
                <img src="assets/image1.jpg" alt="Resource Image 1">
                <p>Image 1 (JPG)</p>
            </div>
            <div class="image-item">
                <img src="assets/image2.png" alt="Resource Image 2">
                <p>Image 2 (PNG)</p>
            </div>
            <div class="image-item">
                <img src="assets/image3.jpg" alt="Resource Image 3">
                <p>Image 3 (JPG)</p>
            </div>
        </div>

        <h2>Interactive Element</h2>
        <div class="highlight-box">
            <p>Click counter (demonstrates JavaScript functionality): <span id="clickCounter">0</span></p>
            <button id="interactiveButton" style="padding: 10px 20px; background: #667eea; color: white; border: none; border-radius: 5px; cursor: pointer;">Click Me!</button>
        </div>

        <h2>Technical Details</h2>
        <p><strong>Page loaded at:</strong> <span id="timestamp">Loading...</span></p>
        <p>This page contains multiple resource types to ensure complete preservation when saving. The "Webpage, Complete" format should create a folder named "demo_page_files" containing all referenced resources.</p>

        <div class="highlight-box">
            <h3>Expected Save Behavior</h3>
            <ul>
                <li>Main HTML file: demo_page.html</li>
                <li>Resources folder: demo_page_files/</li>
                <li>Folder should contain: style.css, script.js, and 3 image files</li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF

chown -R ga:ga "$WEBROOT"
echo "✓ Test webpage created at: $WEBROOT/demo_page.html"

# Start HTTP server in background
echo "Starting HTTP server on port 8765..."
cd "$WEBROOT"
su - ga -c "cd $WEBROOT && python3 -m http.server 8765 > /tmp/http_server.log 2>&1 &"
SERVER_PID=$!
echo $SERVER_PID > /tmp/http_server.pid
sleep 3

# Verify server is running
if curl -s http://localhost:8765/demo_page.html > /dev/null 2>&1; then
    echo "✓ HTTP server is running on port 8765"
else
    echo "⚠ Warning: HTTP server may not be running properly"
fi

# Ensure Chrome is ready
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
TEST_URL="http://localhost:8765/demo_page.html"
echo "Navigating to: $TEST_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TEST_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Wait for page to fully load with all resources
echo "Waiting for page resources to load..."
sleep 2

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the demo page with multiple resources"
echo "Agent should now:"
echo "  1. Press Ctrl+S (or File → Save Page As)"
echo "  2. Select 'Webpage, Complete' from format dropdown"
echo "  3. Name the file: demo_page"
echo "  4. Save to Downloads folder"
echo ""
echo "Expected result:"
echo "  - /home/ga/Downloads/demo_page.html"
echo "  - /home/ga/Downloads/demo_page_files/ (folder with resources)"