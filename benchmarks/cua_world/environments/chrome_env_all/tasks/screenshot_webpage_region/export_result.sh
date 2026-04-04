#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Screenshot Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one more time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Give a moment for any final screenshot save operations to complete
sleep 2

# Create verification directory
VERIFY_DIR="/tmp/screenshot_verification"
mkdir -p "$VERIFY_DIR"

# Look for screenshot files in Downloads
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for screenshot files in Downloads folder..."

# Find any screenshot files (Chrome typically names them "Screenshot YYYY-MM-DD at HH.MM.SS.png")
SCREENSHOT_FILES=$(find "$DOWNLOADS_DIR" -name "Screenshot*.png" -o -name "screenshot*.png" 2>/dev/null | sort -r)

if [ -n "$SCREENSHOT_FILES" ]; then
    SCREENSHOT_COUNT=$(echo "$SCREENSHOT_FILES" | wc -l)
    echo "✓ Found $SCREENSHOT_COUNT screenshot file(s)"
    
    # Get the most recent screenshot
    MOST_RECENT=$(echo "$SCREENSHOT_FILES" | head -1)
    echo "Most recent screenshot: $MOST_RECENT"
    
    # Copy the most recent screenshot to verification directory
    cp "$MOST_RECENT" "$VERIFY_DIR/captured_screenshot.png"
    echo "$MOST_RECENT" > "$VERIFY_DIR/screenshot_filename.txt"
    
    # Get file info
    ls -lh "$MOST_RECENT" | tee "$VERIFY_DIR/screenshot_info.txt"
    
    # Copy all screenshots for debugging
    cp "$DOWNLOADS_DIR"/Screenshot*.png "$VERIFY_DIR/" 2>/dev/null || true
    cp "$DOWNLOADS_DIR"/screenshot*.png "$VERIFY_DIR/" 2>/dev/null || true
else
    echo "⚠ No screenshot files found in Downloads"
    echo "none" > "$VERIFY_DIR/screenshot_filename.txt"
    
    # List Downloads folder contents for debugging
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" || true
fi

# Copy task start time for verification
if [ -f /tmp/screenshot_task_start_time.txt ]; then
    cp /tmp/screenshot_task_start_time.txt "$VERIFY_DIR/"
fi

# Capture active tab URL for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot of the desktop for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/desktop_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved for debugging"
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"