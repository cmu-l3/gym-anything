#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Content Blocking Task Setup ==="
echo "Task: Block JavaScript for a specific heavy website to improve performance"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create the test "heavy" website
echo "Creating test heavy website..."
TEST_SITE_DIR="/home/ga/Documents"
mkdir -p "$TEST_SITE_DIR"

cat > "$TEST_SITE_DIR/test_heavy_site.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Heavy Content Test Site - News Portal</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .header {
            background-color: #333;
            color: white;
            padding: 20px;
            text-align: center;
        }
        .content {
            background-color: white;
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .ad-banner {
            background-color: #ff6b6b;
            color: white;
            padding: 40px;
            text-align: center;
            margin: 20px 0;
            font-size: 24px;
        }
        #heavy-script-indicator {
            background-color: #4CAF50;
            color: white;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
            text-align: center;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>📰 Heavy News Portal - Test Site</h1>
        <p>This site simulates heavy JavaScript and resource-intensive content</p>
    </div>

    <div class="content">
        <h2>Welcome to Our News Site</h2>
        <p>This website represents a typical news portal with heavy JavaScript tracking, 
        auto-playing video ads, and resource-intensive scripts that can slow down 
        older computers and browsers.</p>
        
        <p>In real-world scenarios, blocking JavaScript on sites like this can dramatically 
        improve page load times and system responsiveness, especially on computers with 
        limited resources.</p>
    </div>

    <div class="ad-banner">
        🎬 AUTO-PLAYING VIDEO AD (Simulated)
    </div>

    <div id="heavy-script-indicator">
        ⚠️ HEAVY JAVASCRIPT IS RUNNING
    </div>

    <div class="content">
        <h3>Breaking News Stories</h3>
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. This content would 
        normally be surrounded by dozens of tracking scripts, analytics code, and 
        advertising frameworks.</p>
        
        <ul>
            <li>Technology: Latest gadget releases</li>
            <li>Business: Market updates and analysis</li>
            <li>Sports: Championship results</li>
            <li>Entertainment: Celebrity news</li>
        </ul>
    </div>

    <div class="ad-banner">
        💰 SPONSORED CONTENT (Simulated)
    </div>

    <script>
        // Simulate heavy JavaScript operations
        console.log("Heavy JavaScript is executing...");
        
        // Update the indicator
        document.getElementById('heavy-script-indicator').textContent = 
            '✅ JAVASCRIPT IS ACTIVE - Heavy scripts running';
        document.getElementById('heavy-script-indicator').style.backgroundColor = '#ff9800';
        
        // Simulate tracking scripts
        for (let i = 0; i < 100; i++) {
            console.log(`Tracking event ${i}: User interaction logged`);
        }
        
        // Simulate analytics
        console.log("Analytics initialized");
        console.log("Ad frameworks loaded");
        console.log("Video player scripts active");
    </script>

    <div class="content">
        <p><strong>Note:</strong> When JavaScript is blocked for this site, the page will 
        load much faster, consume less memory, and stop executing resource-intensive scripts. 
        The green indicator above will not change to orange if JavaScript is successfully blocked.</p>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_SITE_DIR/test_heavy_site.html"
echo "✓ Test heavy site created at: $TEST_SITE_DIR/test_heavy_site.html"

# Set the target URL for the task
TARGET_URL="file:///home/ga/Documents/test_heavy_site.html"
echo "Target site URL: $TARGET_URL"

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

# Navigate to the test heavy site
echo "Navigating to: $TARGET_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '$TARGET_URL'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    
    # Check that we're on the correct page
    CURRENT_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    echo "Current URL: $CURRENT_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the test heavy website"
echo ""
echo "Agent should now:"
echo "  1. Click on the padlock/info icon to the left of the URL in the address bar"
echo "  2. Click 'Site settings' in the popup"
echo "  3. Find the 'JavaScript' permission"
echo "  4. Change JavaScript from 'Allow' to 'Block'"
echo "  5. The setting will be saved automatically"
echo ""
echo "Expected outcome: JavaScript blocked for file:///home/ga/Documents/test_heavy_site.html"