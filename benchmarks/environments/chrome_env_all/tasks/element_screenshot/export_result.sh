#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DOM Element Screenshot Task Export: element_screenshot@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/element_screenshot_verification"
mkdir -p "$VERIFY_DIR"

# Capture viewport dimensions via CDP
echo "Capturing viewport dimensions via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    # Get the active tab's WebSocket URL
    WS_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' /tmp/chrome_tabs.json)
    
    if [ -n "$WS_URL" ]; then
        echo "✓ Active tab found"
        
        # Use JavaScript to get viewport and element dimensions
        # We'll use Runtime.evaluate via CDP
        VIEWPORT_INFO=$(curl -s http://localhost:9222/json/version 2>/dev/null | jq -r '.webSocketDebuggerUrl // ""')
        
        # Simpler approach: just execute JavaScript via tab
        TAB_ID=$(jq -r '[.[] | select(.type == "page")][0].id // ""' /tmp/chrome_tabs.json)
        
        # Get viewport dimensions
        echo '{"method":"Runtime.evaluate","params":{"expression":"JSON.stringify({viewportWidth: window.innerWidth, viewportHeight: window.innerHeight, elementWidth: document.getElementById(\"target-card\").offsetWidth, elementHeight: document.getElementById(\"target-card\").offsetHeight})"}}' > /tmp/cdp_command.json
        
        # Save tab info for verifier
        cp /tmp/chrome_tabs.json "$VERIFY_DIR/chrome_tabs.json"
        echo "Viewport and element info captured"
    fi
else
    echo "⚠ Warning: Failed to access CDP"
fi

# Find and copy screenshot files from Downloads
echo "Searching for screenshot files in Downloads folder..."
DOWNLOADS_DIR="/home/ga/Downloads"

if [ -d "$DOWNLOADS_DIR" ]; then
    # Find PNG files created in the last 3 minutes
    SCREENSHOT_COUNT=0
    
    while IFS= read -r -d '' png_file; do
        if [ -f "$png_file" ]; then
            FILE_NAME=$(basename "$png_file")
            FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$png_file") ))
            
            # Only consider files created in last 180 seconds
            if [ $FILE_AGE -lt 180 ]; then
                echo "Found recent PNG: $FILE_NAME (${FILE_AGE}s old)"
                cp "$png_file" "$VERIFY_DIR/"
                echo "$FILE_NAME" >> "$VERIFY_DIR/screenshot_files.txt"
                SCREENSHOT_COUNT=$((SCREENSHOT_COUNT + 1))
            fi
        fi
    done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -name "*.png" -type f -print0 2>/dev/null)
    
    echo "✓ Found $SCREENSHOT_COUNT recent PNG file(s)"
    
    # List all files in Downloads for debugging
    echo "All files in Downloads:"
    ls -lht "$DOWNLOADS_DIR" | head -10 || true
else
    echo "⚠ Downloads directory not found"
    echo "none" > "$VERIFY_DIR/screenshot_files.txt"
fi

# Capture active tab URL
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot of the entire desktop for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_desktop_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved"
fi

# Copy verification directory contents to standard location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"