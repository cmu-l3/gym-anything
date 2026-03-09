#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network HAR Export Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/har_export_verification"
mkdir -p "$VERIFY_DIR"

# Look for HAR file in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for HAR file in Downloads folder..."

# Find the most recently modified HAR file
RECENT_HAR=$(find "$DOWNLOADS_DIR" -name "*.har" -type f -mmin -10 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -n "$RECENT_HAR" ] && [ -f "$RECENT_HAR" ]; then
    HAR_FILENAME=$(basename "$RECENT_HAR")
    echo "✓ Found HAR file: $HAR_FILENAME"
    echo "$HAR_FILENAME" > "$VERIFY_DIR/har_filename.txt"
    
    # Copy HAR file to verification directory
    cp "$RECENT_HAR" "$VERIFY_DIR/"
    
    # Get file size for logging
    HAR_SIZE=$(stat -f%z "$RECENT_HAR" 2>/dev/null || stat -c%s "$RECENT_HAR" 2>/dev/null || echo "unknown")
    echo "HAR file size: $HAR_SIZE bytes"
    echo "$HAR_SIZE" > "$VERIFY_DIR/har_size.txt"
    
    # Preview first few lines of HAR for debugging (without breaking JSON)
    head -c 500 "$RECENT_HAR" > "$VERIFY_DIR/har_preview.txt" 2>/dev/null || true
else
    echo "⚠ No HAR file found in Downloads folder"
    echo "none" > "$VERIFY_DIR/har_filename.txt"
    
    # List all files in Downloads for debugging
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" 2>/dev/null || echo "Could not list Downloads folder"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Stop the demo HTTP server
if [ -f /tmp/har_demo_server.pid ]; then
    SERVER_PID=$(cat /tmp/har_demo_server.pid)
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo "Stopping demo HTTP server (PID: $SERVER_PID)..."
        kill $SERVER_PID 2>/dev/null || true
        sleep 1
    fi
    rm /tmp/har_demo_server.pid
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"