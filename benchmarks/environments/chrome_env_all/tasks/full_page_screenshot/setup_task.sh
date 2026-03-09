#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Full-Page Screenshot Task Setup ==="
echo "Task: Capture full-page screenshot using Chrome DevTools"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install image processing libraries for verification
pip3 install -q Pillow numpy 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create a long article HTML file for screenshot testing
echo "Creating test article HTML..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/long_article.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Full-Page Screenshot Test Article</title>
    <style>
        body {
            font-family: Georgia, serif;
            line-height: 1.8;
            margin: 0;
            padding: 40px 60px;
            max-width: 900px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 60px;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #2c3e50;
            font-size: 2.8em;
            margin-top: 0;
            margin-bottom: 30px;
            border-bottom: 4px solid #667eea;
            padding-bottom: 20px;
        }
        h2 {
            color: #34495e;
            font-size: 2em;
            margin-top: 50px;
            margin-bottom: 20px;
        }
        p {
            margin: 15px 0;
            text-align: justify;
            color: #333;
            font-size: 1.1em;
        }
        .highlight {
            background-color: #fff3cd;
            border-left: 5px solid #ffc107;
            padding: 20px;
            margin: 30px 0;
            border-radius: 5px;
        }
        .section {
            margin-bottom: 60px;
            padding: 30px 0;
            border-bottom: 1px solid #e0e0e0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>The Art and Science of Full-Page Screenshots</h1>
        
        <p><em>A comprehensive exploration of webpage capture techniques, their applications, and best practices for documentation and design workflows.</em></p>

        <div class="section">
            <h2>Introduction: Why Full-Page Screenshots Matter</h2>
            
            <p>In the digital age, the ability to capture entire web pages—beyond what's visible in the browser viewport—has become an essential skill for web developers, designers, quality assurance professionals, and content creators. Unlike traditional screenshot methods that capture only the visible portion of a screen, full-page screenshots preserve the complete vertical and horizontal extent of a webpage, providing a comprehensive visual record.</p>

            <p>This capability is particularly valuable when documenting complex web applications, archiving content for legal or compliance purposes, reviewing design implementations, reporting bugs that span multiple screen heights, or creating portfolio presentations that showcase entire page layouts.</p>
        </div>

        <div class="section">
            <h2>Technical Foundations</h2>
            
            <p>The browser viewport represents the visible rectangular area within which web content is displayed. Typically ranging from 1280×720 to 1920×1080 pixels on desktop systems, the viewport shows only a fraction of many modern web pages, which can extend to thousands of pixels vertically due to scrollable content.</p>

            <p>Full-page screenshots overcome viewport limitations by programmatically capturing the entire rendered document, from the topmost header to the final footer element. This process involves sophisticated coordination between the browser's rendering engine and screenshot capture mechanisms.</p>

            <div class="highlight">
                <strong>Chrome DevTools</strong> provides built-in screenshot functionality that surpasses third-party browser extensions in reliability and quality. Accessible through the Command Palette (Ctrl+Shift+P), DevTools offers several screenshot modes including the "Capture full size screenshot" option.
            </div>
        </div>

        <div class="section">
            <h2>Practical Applications</h2>
            
            <p><strong>Web Development and Quality Assurance:</strong> Development teams use full-page screenshots extensively during regression testing to compare page renderings across different browser versions, operating systems, or code branches.</p>

            <p><strong>Design Documentation:</strong> Design agencies and freelance web designers frequently need to document completed work for portfolios, case studies, or client approval processes. Full-page screenshots provide comprehensive visual records.</p>

            <p><strong>Legal and Compliance:</strong> Legal professionals rely on full-page screenshots to preserve evidence of website states at specific points in time, documenting terms of service, pricing information, or advertising claims.</p>
        </div>

        <div class="section">
            <h2>Best Practices</h2>
            
            <p>Optimal screenshot timing requires ensuring that all page resources—images, fonts, stylesheets, scripts—have fully loaded and rendered before capture. Modern websites employ lazy loading and dynamic content injection.</p>

            <p>Pages with animations, carousels, or interactive widgets present special challenges. Establishing clear capture protocols ensures consistency across multiple screenshots.</p>

            <p>DevTools captures screenshots at the page's natural rendering resolution, respecting device pixel ratios and zoom levels. PNG format provides lossless compression suitable for text-heavy pages.</p>
        </div>

        <div class="section">
            <h2>Common Challenges</h2>
            
            <p><strong>Extremely Long Pages:</strong> Infinite scroll implementations can result in memory constraints. Solutions include capturing pages in segments or using specialized screenshot services.</p>

            <p><strong>Responsive Designs:</strong> Capturing at mobile viewport sizes requires enabling Chrome's device emulation mode before screenshot capture.</p>

            <p><strong>Authentication:</strong> Pages behind login walls necessitate establishing browser sessions with appropriate cookies or tokens before capture.</p>
        </div>

        <div class="section">
            <h2>Verification and Quality</h2>
            
            <p>After capture, screenshots should be inspected for completeness, quality, accuracy, and rendering artifacts. Does the capture include the entire page height? Are text and images sharp?</p>

            <p>Programmatic verification can validate screenshot quality by examining image metadata, pixel dimensions, file sizes, and content checksums. Expected page heights can be compared against capture heights.</p>
        </div>

        <div class="section">
            <h2>Future Trends</h2>
            
            <p><strong>AI-Powered Analysis:</strong> Machine learning models are increasingly being applied to screenshot analysis, enabling automated detection of visual anomalies and accessibility issues.</p>

            <p><strong>Collaborative Annotation:</strong> Modern tools integrate screenshot capture with real-time annotation and issue tracking for design feedback.</p>

            <p><strong>Digital Preservation:</strong> Cultural institutions explore screenshot-based preservation strategies to capture visual presentations alongside source code.</p>
        </div>

        <div class="section">
            <h2>Conclusion</h2>
            
            <p>Full-page screenshot capture has evolved from a niche technical skill to an essential capability for modern web professionals. Chrome DevTools' built-in functionality provides a robust, accessible foundation for these workflows.</p>

            <p>By understanding technical foundations, following best practices, and applying verification techniques, practitioners can leverage full-page screenshots as powerful documentation tools in their digital workflow arsenals.</p>
        </div>

        <div style="margin-top: 60px; padding: 30px; background: #f8f9fa; border-radius: 5px; text-align: center;">
            <p><strong>End of Article</strong></p>
            <p>This document was designed to test full-page screenshot capture functionality.</p>
            <p>Total page height: Approximately 2500+ pixels</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/long_article.html"
echo "✓ Test article created at: $ARTICLE_DIR/long_article.html"

# Ensure Downloads directory exists and is clean
echo "Preparing Downloads directory..."
mkdir -p /home/ga/Downloads
# Remove any existing screenshot files to avoid confusion
rm -f /home/ga/Downloads/screenshot*.png
rm -f /home/ga/Downloads/*.png
chown -R ga:ga /home/ga/Downloads
echo "✓ Downloads directory ready"

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

# Navigate to the test article
ARTICLE_URL="file:///home/ga/Documents/long_article.html"
echo "Navigating to: $ARTICLE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/long_article.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '.[0].url // "unknown"')
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Record task start time for verification
date +%s > /tmp/task_start_time.txt
echo "✓ Task start time recorded"

echo "=== Setup complete ==="
echo "Chrome is displaying the test article."
echo ""
echo "Agent should:"
echo "  1. Press F12 (or Ctrl+Shift+I) to open Chrome DevTools"
echo "  2. Press Ctrl+Shift+P to open DevTools Command Palette"
echo "  3. Type 'screenshot' to search for screenshot commands"
echo "  4. Select 'Capture full size screenshot' from the menu"
echo "  5. Wait for screenshot to be saved to Downloads folder"
echo ""
echo "The screenshot should capture the entire ~2500px tall article."