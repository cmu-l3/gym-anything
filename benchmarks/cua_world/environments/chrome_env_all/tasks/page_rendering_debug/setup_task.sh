#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Rendering Debug Task Setup ==="
echo "Task: Diagnose and fix CSS rendering issue using DevTools"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip imagemagick || true

# Install Python libraries for verification
pip3 install -q pillow scikit-image 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create directory for test page
TEST_PAGE_DIR="/home/ga/Documents/debug_test"
mkdir -p "$TEST_PAGE_DIR"

echo "Creating test webpage with CSS rendering issue..."

# Create the HTML page that references external CSS
cat > "$TEST_PAGE_DIR/test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Product Launch Page</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>Introducing TechFlow Pro</h1>
        <p class="subtitle">The Future of Productivity</p>
    </header>
    
    <main>
        <section class="features">
            <div class="feature-card">
                <h2>Lightning Fast</h2>
                <p>Experience unprecedented speed with our advanced processing technology.</p>
            </div>
            
            <div class="feature-card">
                <h2>Secure & Private</h2>
                <p>Your data is protected with military-grade encryption.</p>
            </div>
            
            <div class="feature-card">
                <h2>Cloud Sync</h2>
                <p>Access your work from anywhere, on any device.</p>
            </div>
        </section>
        
        <section class="cta">
            <h2>Ready to Transform Your Workflow?</h2>
            <button class="cta-button">Get Started Free</button>
            <p class="pricing">No credit card required. 30-day trial.</p>
        </section>
    </main>
    
    <footer>
        <p>&copy; 2024 TechFlow Inc. All rights reserved.</p>
    </footer>
</body>
</html>
EOF

# Create the reference "working" CSS (this will be used for final comparison)
cat > "$TEST_PAGE_DIR/styles_reference.css" << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: #333;
    line-height: 1.6;
}

header {
    background: rgba(255, 255, 255, 0.95);
    padding: 60px 40px;
    text-align: center;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

h1 {
    font-size: 48px;
    color: #667eea;
    margin-bottom: 10px;
    text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.1);
}

.subtitle {
    font-size: 24px;
    color: #666;
    font-style: italic;
}

main {
    max-width: 1200px;
    margin: 40px auto;
    padding: 20px;
}

.features {
    display: flex;
    gap: 30px;
    margin-bottom: 60px;
    flex-wrap: wrap;
    justify-content: center;
}

.feature-card {
    background: white;
    border-radius: 15px;
    padding: 30px;
    flex: 1;
    min-width: 280px;
    max-width: 350px;
    box-shadow: 0 8px 16px rgba(0, 0, 0, 0.2);
    transition: transform 0.3s ease;
}

.feature-card:hover {
    transform: translateY(-5px);
}

.feature-card h2 {
    color: #764ba2;
    font-size: 28px;
    margin-bottom: 15px;
}

.feature-card p {
    color: #555;
    font-size: 16px;
}

.cta {
    background: rgba(255, 255, 255, 0.95);
    border-radius: 20px;
    padding: 60px 40px;
    text-align: center;
    box-shadow: 0 8px 16px rgba(0, 0, 0, 0.2);
}

.cta h2 {
    font-size: 36px;
    color: #333;
    margin-bottom: 30px;
}

.cta-button {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border: none;
    padding: 18px 50px;
    font-size: 20px;
    border-radius: 50px;
    cursor: pointer;
    box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
    transition: all 0.3s ease;
    font-weight: bold;
}

.cta-button:hover {
    transform: scale(1.05);
    box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6);
}

.pricing {
    margin-top: 20px;
    color: #666;
    font-size: 14px;
}

footer {
    background: rgba(0, 0, 0, 0.2);
    color: white;
    text-align: center;
    padding: 20px;
    margin-top: 40px;
}
EOF

# Initially, DO NOT create styles.css - this will cause 404 error
# We'll create it later to simulate the "fixed" version being available
echo "CSS file intentionally not created yet (will cause 404 error)"

# Set proper ownership
chown -R ga:ga "$TEST_PAGE_DIR"

# Ensure Chrome is running
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

# IMPORTANT: Click at center to select desktop
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

# Navigate to the test page (CSS will fail to load, showing broken styling)
PAGE_URL="file://${TEST_PAGE_DIR}/test_page.html"
echo "Navigating to test page: $PAGE_URL"

su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 '${PAGE_URL}'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Capture the "broken" state screenshot
echo "Capturing initial broken state screenshot..."
su - ga -c "DISPLAY=:1 import -window root /tmp/screenshot_broken_initial.png" 2>/dev/null || true

# Now create the CSS file so it's available (but browser has cached the 404)
echo "Creating styles.css (browser still has cached 404 error)..."
cp "$TEST_PAGE_DIR/styles_reference.css" "$TEST_PAGE_DIR/styles.css"
chown ga:ga "$TEST_PAGE_DIR/styles.css"

# Do a regular refresh to show that the issue persists (cached 404)
sleep 1
echo "Refreshing page (issue persists due to cached error)..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers F5" || true
sleep 2

# Capture this "still broken" state
echo "Capturing 'still broken' state after normal refresh..."
su - ga -c "DISPLAY=:1 import -window root /tmp/screenshot_broken_after_refresh.png" 2>/dev/null || true

# Save the reference "correct" screenshot by doing a hard reload manually
echo "Creating reference 'correct' screenshot..."
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+r" || true
sleep 3
su - ga -c "DISPLAY=:1 import -window root /tmp/screenshot_correct_reference.png" 2>/dev/null || true

# Navigate back to broken state (normal reload will show cached error again)
# Actually, after hard reload it's fixed. So let's create the broken scenario again.
# Delete CSS and reload
rm "$TEST_PAGE_DIR/styles.css"
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers F5" || true
sleep 2

# Now recreate CSS
cp "$TEST_PAGE_DIR/styles_reference.css" "$TEST_PAGE_DIR/styles.css"
chown ga:ga "$TEST_PAGE_DIR/styles.css"

# Normal refresh - should still show broken due to cache
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers F5" || true
sleep 2

# Final focus
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Create a marker file with task state
cat > /tmp/rendering_debug_state.txt << EOF
test_page_path=$TEST_PAGE_DIR/test_page.html
css_exists=true
broken_state_captured=true
reference_screenshot_exists=true
EOF

echo "=== Setup complete ==="
echo ""
echo "Current state:"
echo "  - Test page loaded at: file://$TEST_PAGE_DIR/test_page.html"
echo "  - CSS file exists but browser has cached 404 error"
echo "  - Page appears unstyled/broken"
echo ""
echo "Agent task:"
echo "  1. Recognize the page has rendering issues"
echo "  2. Open DevTools (F12)"
echo "  3. Check Console tab for errors (should see CSS load failure)"
echo "  4. Clear cache and hard reload (Ctrl+Shift+R or DevTools > Empty Cache and Hard Reload)"
echo "  5. Verify page now displays with correct styling"