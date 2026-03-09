#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Find in Page Navigation Task Setup: find_in_page_multi_match@1 ==="
echo "Task: Use Find in Page to search for 'example' and navigate through matches"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-requests || true

# Wait for environment to be ready
sleep 2

# Create the test HTML page with known searchable content
echo "Creating test HTML page with searchable content..."
TEST_HTML_DIR="/home/ga/Documents"
mkdir -p "$TEST_HTML_DIR"

cat > "$TEST_HTML_DIR/find_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Find in Page Test Document</title>
    <style>
        body {
            font-family: 'Georgia', serif;
            line-height: 1.8;
            margin: 40px;
            max-width: 800px;
            background-color: #f9f9f9;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        h2 {
            color: #34495e;
            margin-top: 30px;
        }
        p {
            margin: 15px 0;
            text-align: justify;
        }
        .highlight-box {
            background-color: #e8f4f8;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>Test Document for Find Functionality</h1>
    
    <h2>Introduction</h2>
    <p>This is a test document designed to help you practice using the Find in Page feature. 
    The word "example" appears multiple times throughout this document. Your task is to locate 
    specific occurrences of this search term using Chrome's built-in find functionality.</p>
    
    <h2>First Section</h2>
    <p>In this first section, we present an <strong>example</strong> of how search terms can be 
    embedded in various contexts. This example demonstrates basic text searching capabilities.</p>
    
    <p>When searching for words in a document, each example helps you understand the distribution 
    and context of your search query. Finding multiple instances is a common use case.</p>
    
    <div class="highlight-box">
        <p><strong>Important Note:</strong> The third example in this document is particularly 
        significant for completing your task. Pay attention to which occurrence you're viewing.</p>
    </div>
    
    <h2>Second Section</h2>
    <p>As you navigate through the document, you'll encounter additional example text that serves 
    different purposes. Each example provides a unique context for understanding search behavior.</p>
    
    <p>The fifth example appears in this paragraph, demonstrating how search results can span 
    across different document sections and structural elements.</p>
    
    <h2>Final Section</h2>
    <p>Near the end of the document, we include yet another example to ensure adequate test 
    coverage. This penultimate example helps verify navigation accuracy.</p>
    
    <p>The final example appears here in the last paragraph, completing the set of eight total 
    occurrences that are distributed throughout the document.</p>
    
    <h2>Summary</h2>
    <p>This document contains exactly eight instances of the target search term. Using the Find 
    in Page feature allows you to navigate sequentially through all matches, observing the match 
    counter and current position indicator.</p>
    
</body>
</html>
EOF

chown ga:ga "$TEST_HTML_DIR/find_test_page.html"
echo "✓ Test HTML page created at: $TEST_HTML_DIR/find_test_page.html"

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

# Navigate to the test HTML page
TEST_PAGE_URL="file:///home/ga/Documents/find_test_page.html"
echo "Navigating to: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/find_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active and page is loaded
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    ACTIVE_URL=$(curl -s http://localhost:9222/json | jq -r '[.[] | select(.type == "page")][0].url // ""' || echo "unknown")
    echo "✓ Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the test document at: $TEST_PAGE_URL"
echo ""
echo "Agent task:"
echo "  1. Press Ctrl+F to open Find in Page"
echo "  2. Type 'example' in the search box"
echo "  3. Press Enter twice to navigate to the 3rd occurrence"
echo "  4. Observe the match counter (should show '3 of 8')"