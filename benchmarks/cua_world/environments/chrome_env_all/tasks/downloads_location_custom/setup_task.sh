#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Downloads Location Task Setup ==="
echo "Task: Configure custom download location and verify with test download"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Ensure CustomDownloads directory does NOT exist initially (clean slate)
echo "Ensuring clean state..."
rm -rf /home/ga/CustomDownloads
rm -f /home/ga/Downloads/test_download.pdf 2>/dev/null || true

# Create test download file and HTTP server
echo "Setting up test download server..."
TEST_SERVER_DIR="/tmp/test_download_server"
mkdir -p "$TEST_SERVER_DIR"

# Create a test PDF file for download
cat > "$TEST_SERVER_DIR/test_download.pdf" << 'EOF'
%PDF-1.4
1 0 obj
<<
/Type /Catalog
/Pages 2 0 R
>>
endobj
2 0 obj
<<
/Type /Pages
/Kids [3 0 R]
/Count 1
>>
endobj
3 0 obj
<<
/Type /Page
/Parent 2 0 R
/Resources <<
/Font <<
/F1 <<
/Type /Font
/Subtype /Type1
/BaseFont /Helvetica
>>
>>
>>
/MediaBox [0 0 612 792]
/Contents 4 0 R
>>
endobj
4 0 obj
<<
/Length 44
>>
stream
BT
/F1 12 Tf
100 700 Td
(Test Download File) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000317 00000 n 
trailer
<<
/Size 5
/Root 1 0 R
>>
startxref
410
%%EOF
EOF

echo "✓ Test PDF created at: $TEST_SERVER_DIR/test_download.pdf"

# Start HTTP server on port 8765 for test downloads
echo "Starting HTTP server on port 8765..."
cd "$TEST_SERVER_DIR"
python3 -m http.server 8765 > /tmp/download_server.log 2>&1 &
HTTP_SERVER_PID=$!
echo $HTTP_SERVER_PID > /tmp/download_server.pid
echo "✓ HTTP server started (PID: $HTTP_SERVER_PID)"

# Wait for server to be ready
sleep 2

# Verify server is running
if curl -s http://localhost:8765/test_download.pdf > /dev/null 2>&1; then
    echo "✓ Test download available at: http://localhost:8765/test_download.pdf"
else
    echo "⚠ Warning: Test download server may not be ready"
fi

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

# Navigate to the starting URL (Google homepage)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Agent should now:"
echo "  1. Navigate to chrome://settings/downloads"
echo "  2. Click 'Change' button next to Location"
echo "  3. Create/select folder: /home/ga/CustomDownloads"
echo "  4. Navigate to http://localhost:8765/test_download.pdf"
echo "  5. Download will automatically start"
echo ""
echo "Test download URL: http://localhost:8765/test_download.pdf"