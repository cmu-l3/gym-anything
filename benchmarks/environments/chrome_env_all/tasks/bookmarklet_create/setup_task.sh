#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome JavaScript Bookmarklet Creation Task Setup ==="
echo "Task: Create a bookmarklet named 'Page Highlighter' that highlights paragraphs with yellow background"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create test HTML page with paragraphs for bookmarklet testing
echo "Creating test HTML page with paragraphs..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/bookmarklet_test_page.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bookmarklet Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.8;
            margin: 40px;
            max-width: 800px;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
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
        .info-box {
            background-color: #ecf0f1;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <h1>Test Page for Bookmarklet Functionality</h1>
    
    <div class="info-box">
        <strong>Instructions:</strong> This page contains multiple paragraph elements. 
        After creating your bookmarklet, click it to see all paragraphs highlighted with yellow background.
    </div>
    
    <h2>What is a Bookmarklet?</h2>
    
    <p>A bookmarklet is a bookmark stored in a web browser that contains JavaScript code instead of a URL. 
    When clicked, it executes the JavaScript code in the context of the current page, allowing users to 
    perform custom actions without installing browser extensions.</p>
    
    <p>Bookmarklets are created using the special <code>javascript:</code> protocol in the bookmark URL field. 
    The JavaScript code following this protocol is executed when the user clicks the bookmark.</p>
    
    <h2>Common Use Cases</h2>
    
    <p>Web developers and power users employ bookmarklets for various productivity enhancements. 
    Popular uses include stripping page formatting for easier reading, extracting specific content like 
    images or links, performing quick searches, and manipulating page elements for better accessibility.</p>
    
    <p>Bookmarklets offer a lightweight alternative to full browser extensions for simple, 
    one-click operations. They work across different browsers and don't require installation permissions, 
    making them ideal for quick utilities and personal productivity tools.</p>
    
    <h2>Creating Your First Bookmarklet</h2>
    
    <p>To create a bookmarklet, open your browser's bookmark manager or bookmark bar. 
    Create a new bookmark and enter a descriptive name. In the URL field, type <code>javascript:</code> 
    followed by your JavaScript code.</p>
    
    <p>For this exercise, you should create a bookmarklet that selects all paragraph elements on the page 
    and changes their background color to yellow. This demonstrates DOM manipulation and style modification 
    through bookmarklet execution.</p>
    
    <h2>Testing Your Bookmarklet</h2>
    
    <p>After creating the bookmarklet, test it by clicking on it while viewing this page. 
    If successful, all paragraph elements (like this one) should display with a yellow background color.</p>
    
    <p>The highlighting effect should be immediately visible, demonstrating that the JavaScript code 
    executed correctly in the page context. This confirms your bookmarklet is properly configured and functional.</p>
    
    <h2>Technical Details</h2>
    
    <p>Bookmarklets execute in the global scope of the current page, giving them access to the entire 
    Document Object Model (DOM). They can read and modify page content, respond to user actions, and 
    interact with JavaScript APIs available in the browser environment.</p>
    
    <p>Modern bookmarklets often use self-executing anonymous functions (IIFEs) to avoid polluting the 
    global namespace. This pattern wraps the bookmarklet code in parentheses and immediately invokes it, 
    ensuring clean execution without side effects.</p>
    
    <div class="info-box">
        <strong>Note:</strong> This page contains exactly 10 paragraph elements. 
        Your bookmarklet should highlight all of them when executed successfully.
    </div>
    
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/bookmarklet_test_page.html"
echo "✓ Test HTML page created at: $TEST_PAGE_DIR/bookmarklet_test_page.html"

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

# Ensure bookmark bar is visible (Ctrl+Shift+B to toggle)
echo "Ensuring bookmark bar is visible..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
# Press Ctrl+Shift+B twice to ensure it's in known state, then once more to make it visible
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+b" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+b" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+shift+b" || true
sleep 0.5

# Navigate to the test page
TEST_PAGE_URL="file:///home/ga/Documents/bookmarklet_test_page.html"
echo "Navigating to test page: $TEST_PAGE_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/bookmarklet_test_page.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

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

echo ""
echo "=== Setup complete ==="
echo "Chrome is ready with test page loaded"
echo ""
echo "Agent task instructions:"
echo "  1. Right-click on bookmark bar OR press Ctrl+D to create new bookmark"
echo "  2. Set bookmark name: 'Page Highlighter'"
echo "  3. Set bookmark URL to JavaScript code:"
echo "     javascript:(function(){var s=document.querySelectorAll('p');for(var i=0;i<s.length;i++){s[i].style.backgroundColor='yellow';}})();"
echo "  4. Ensure bookmark is saved to bookmark bar (not 'Other bookmarks')"
echo "  5. Optionally: Click the bookmarklet to test it (paragraphs should turn yellow)"
echo ""
echo "The bookmarklet should select all <p> elements and change their background to yellow."