#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Spell Check Configuration and Custom Dictionary Task Setup ==="
echo "Task: Configure spell check and add custom words to dictionary"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create a test HTML page with text input for spell check testing
echo "Creating test page for spell check verification..."
TEST_PAGE_DIR="/home/ga/Documents"
mkdir -p "$TEST_PAGE_DIR"

cat > "$TEST_PAGE_DIR/spellcheck_test.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spell Check Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        textarea {
            width: 100%;
            min-height: 200px;
            font-size: 16px;
            padding: 15px;
            border: 2px solid #ddd;
            border-radius: 5px;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            resize: vertical;
        }
        textarea:focus {
            outline: none;
            border-color: #4285f4;
        }
        .instructions {
            background-color: #e3f2fd;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            border-left: 4px solid #2196f3;
        }
        .instructions h3 {
            margin-top: 0;
            color: #1976d2;
        }
        .instructions ul {
            margin-bottom: 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔤 Spell Check Test Area</h1>
        
        <div class="instructions">
            <h3>Instructions:</h3>
            <ul>
                <li>Type in the text area below to test spell checking</li>
                <li>Misspelled words will have red underlines</li>
                <li>Right-click on underlined words to add them to your custom dictionary</li>
                <li>Try adding technical terms, proper nouns, or specialized vocabulary</li>
            </ul>
        </div>
        
        <textarea 
            id="testArea" 
            placeholder="Start typing here to test spell check functionality...
            
Try typing these example words to test:
- Technical terms: Kubernetes, TensorFlow, PostgreSQL
- Proper nouns: Pranjal, OSWorld
- Custom words: agentgym, MLOps

Misspelled words will show red underlines. Right-click and select 'Add to dictionary' to add them to your custom dictionary."
            spellcheck="true"
        ></textarea>
    </div>
</body>
</html>
EOF

chown ga:ga "$TEST_PAGE_DIR/spellcheck_test.html"
echo "✓ Test page created at: $TEST_PAGE_DIR/spellcheck_test.html"

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

# Navigate to Chrome settings page for languages
echo "Navigating to: chrome://settings/languages"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings/languages'" || true
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

# Check current spell check configuration for reference
echo "Checking current spell check configuration..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    CURRENT_SPELLCHECK=$(jq -r '.browser.enable_spellchecking // "not set"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
    echo "Current spell check enabled: $CURRENT_SPELLCHECK"
fi

# Check if Custom Dictionary exists and show word count
if [ -f "$CHROME_PROFILE/Custom Dictionary.txt" ]; then
    WORD_COUNT=$(wc -l < "$CHROME_PROFILE/Custom Dictionary.txt" 2>/dev/null || echo "0")
    echo "Custom dictionary currently has $WORD_COUNT word(s)"
else
    echo "Custom dictionary not yet created"
fi

echo "=== Setup complete ==="
echo "Chrome should be on Language settings page"
echo ""
echo "Agent should now:"
echo "  1. Configure spell check settings (enable English spell check)"
echo "  2. Open a new tab (Ctrl+T)"
echo "  3. Navigate to: file:///home/ga/Documents/spellcheck_test.html"
echo "  4. Type in the text area to trigger spell check"
echo "  5. Type custom words (e.g., 'Kubernetes', 'TensorFlow', 'Pranjal')"
echo "  6. Right-click on underlined words"
echo "  7. Select 'Add to dictionary' from context menu"
echo "  8. Verify words are no longer underlined"
echo ""
echo "Test page available at: file:///home/ga/Documents/spellcheck_test.html"