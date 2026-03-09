#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Download Location Task Setup ==="
echo "Task: Configure custom download directory and download a test file"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create test file for downloading
echo "Creating test download file..."
TEST_FILE_DIR="/tmp/download_test_assets"
mkdir -p "$TEST_FILE_DIR"

# Create a test file with recognizable content
TEST_FILE="$TEST_FILE_DIR/test_download_file.txt"
cat > "$TEST_FILE" << 'EOF'
This is a test file for Chrome download location verification.
Created at: $(date)
Purpose: Verify custom download directory configuration
File size: Approximately 500 bytes

Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris.

This file should be downloaded to a custom location instead of ~/Downloads.

Test ID: CHROME_DOWNLOAD_LOCATION_TEST_2024
EOF

echo "✓ Test file created at: $TEST_FILE"
ls -lh "$TEST_FILE"

# Create HTML page with download link
echo "Creating test download webpage..."
DOWNLOAD_PAGE="$TEST_FILE_DIR/download_test_page.html"
cat > "$DOWNLOAD_PAGE" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Download Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            margin: 0;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            padding: 50px;
            text-align: center;
            max-width: 600px;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
            font-size: 32px;
        }
        p {
            color: #666;
            font-size: 16px;
            line-height: 1.6;
            margin-bottom: 30px;
        }
        .download-btn {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            text-decoration: none;
            padding: 18px 40px;
            border-radius: 50px;
            font-size: 18px;
            font-weight: bold;
            transition: transform 0.2s, box-shadow 0.2s;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }
        .download-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.6);
        }
        .download-btn:active {
            transform: translateY(0);
        }
        .instructions {
            margin-top: 40px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        .instructions h3 {
            color: #667eea;
            margin-top: 0;
        }
        .instructions ol {
            text-align: left;
            color: #555;
            line-height: 1.8;
        }
        .icon {
            font-size: 60px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">📥</div>
        <h1>Chrome Download Test</h1>
        <p>This page is designed to test Chrome's custom download location feature.</p>
        
        <a href="test_download_file.txt" download="test_download_file.txt" class="download-btn">
            Download Test File
        </a>
        
        <div class="instructions">
            <h3>Before downloading:</h3>
            <ol>
                <li>Open Chrome Settings (chrome://settings)</li>
                <li>Navigate to "Downloads" section</li>
                <li>Click "Change" next to download location</li>
                <li>Create a new folder (e.g., "MyCustomDownloads")</li>
                <li>Select the folder and confirm</li>
                <li>Return to this page and click download</li>
            </ol>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$DOWNLOAD_PAGE" "$TEST_FILE"
echo "✓ Download page created at: $DOWNLOAD_PAGE"

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

# Navigate to the download test page
DOWNLOAD_URL="file://$DOWNLOAD_PAGE"
echo "Navigating to: $DOWNLOAD_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 30 '$DOWNLOAD_URL'" || true
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

# Check current download directory (should be default)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    CURRENT_DIR=$(jq -r '.download.default_directory // "not_set"' "$CHROME_PROFILE/Preferences" 2>/dev/null)
    echo "Current download directory: $CURRENT_DIR"
fi

echo "=== Setup complete ==="
echo "Chrome should be displaying the download test page"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings/downloads"
echo "  2. Click 'Change' button next to download location"
echo "  3. Create and select a custom folder (e.g., MyCustomDownloads)"
echo "  4. Return to the test page and click the download button"
echo "  5. Wait for download to complete"
echo ""
echo "Expected custom directory: ~/MyCustomDownloads or similar"
echo "Test file name: test_download_file.txt"