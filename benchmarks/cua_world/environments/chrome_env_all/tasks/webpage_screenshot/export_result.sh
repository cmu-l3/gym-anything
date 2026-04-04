#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Webpage Screenshot Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure final state is captured
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Record task end time for verifier
date +%s > /tmp/screenshot_task_end_time.txt
echo "✓ Task end time recorded"

# List all PNG files in Downloads with timestamps
echo "Listing PNG files in Downloads folder..."
DOWNLOADS_DIR="/home/ga/Downloads"
if [ -d "$DOWNLOADS_DIR" ]; then
    ls -lh "$DOWNLOADS_DIR"/*.png 2>/dev/null || echo "No PNG files found"
    
    # Copy list of files with timestamps to temp for verification
    find "$DOWNLOADS_DIR" -name "*.png" -type f -printf "%T@ %p %s\n" 2>/dev/null | sort -rn > /tmp/screenshot_files_list.txt || true
    echo "✓ File list saved to /tmp/screenshot_files_list.txt"
else
    echo "⚠ Warning: Downloads directory not found"
    touch /tmp/screenshot_files_list.txt
fi

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    echo "$ACTIVE_TITLE" > /tmp/final_title.txt
fi

# Take a final screenshot of the desktop for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_desktop_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved to /tmp/final_desktop_screenshot.png"
fi

# Export the most recent PNG from Downloads to temp for easier verification
LATEST_PNG=$(find "$DOWNLOADS_DIR" -name "*.png" -type f -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$LATEST_PNG" ] && [ -f "$LATEST_PNG" ]; then
    PNG_NAME=$(basename "$LATEST_PNG")
    cp "$LATEST_PNG" /tmp/latest_screenshot.png 2>/dev/null || true
    echo "✓ Latest screenshot copied to /tmp/latest_screenshot.png"
    echo "$PNG_NAME" > /tmp/latest_screenshot_name.txt
    ls -lh "$LATEST_PNG"
else
    echo "⚠ No screenshot found in Downloads"
    echo "none" > /tmp/latest_screenshot_name.txt
fi

echo "✅ Export complete"
echo "Verification files prepared in /tmp/"