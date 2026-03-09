#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Complete Webpage Save Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# List Downloads folder contents for debugging
echo "Listing Downloads folder contents..."
DOWNLOADS_DIR="/home/ga/Downloads"
if [ -d "$DOWNLOADS_DIR" ]; then
    echo "Downloads folder contents:"
    ls -lah "$DOWNLOADS_DIR" || true
    
    # Look for the saved HTML file and resources folder
    if [ -f "$DOWNLOADS_DIR/demo_page.html" ]; then
        echo "✓ Found demo_page.html"
        ls -lh "$DOWNLOADS_DIR/demo_page.html"
    fi
    
    if [ -d "$DOWNLOADS_DIR/demo_page_files" ]; then
        echo "✓ Found demo_page_files folder"
        ls -lah "$DOWNLOADS_DIR/demo_page_files" || true
    fi
else
    echo "⚠ Warning: Downloads folder not found"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Stop HTTP server
echo "Stopping HTTP server..."
if [ -f /tmp/http_server.pid ]; then
    HTTP_PID=$(cat /tmp/http_server.pid)
    kill $HTTP_PID 2>/dev/null || true
    rm -f /tmp/http_server.pid
fi
pkill -f "python3 -m http.server 8765" || true

echo "✅ Export complete"
echo "Verification will check for HTML file and resources folder in Downloads"