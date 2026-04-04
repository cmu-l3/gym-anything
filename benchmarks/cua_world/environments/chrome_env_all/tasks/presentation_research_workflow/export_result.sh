#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multi-Source Presentation Research Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL and all tabs via CDP before closing
echo "Capturing browser state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to page-type tabs only
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs.json > /tmp/chrome_page_tabs.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs for logging
    jq -r '.[] | .url' /tmp/chrome_page_tabs.json > /tmp/visited_urls.txt
    echo "Visited URLs:"
    cat /tmp/visited_urls.txt
else
    echo "⚠ Warning: Could not capture CDP state"
    echo "[]" > /tmp/chrome_page_tabs.json
    touch /tmp/visited_urls.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure bookmarks and history are persisted to disk
echo "Closing Chrome to save bookmarks and history..."
pkill -TERM chrome 2>/dev/null || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" 2>/dev/null || true
    sleep 1
fi

# Export Chrome data files for verification
echo "Exporting Chrome bookmarks and history..."

# Try multiple possible profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

BOOKMARKS_EXPORTED=false
HISTORY_EXPORTED=false

for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
        BOOKMARKS_EXPORTED=true
        
        # Also copy History if available
        if [ -f "$CHROME_PROFILE/History" ]; then
            cp "$CHROME_PROFILE/History" /tmp/history_export.db
            echo "✓ History exported from: $CHROME_PROFILE/History"
            HISTORY_EXPORTED=true
        fi
        break
    fi
done

if [ "$BOOKMARKS_EXPORTED" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any profile location"
fi

if [ "$HISTORY_EXPORTED" = false ]; then
    echo "⚠ Warning: History file not found"
fi

# List and export Downloads folder contents
echo "Checking Downloads folder..."
DOWNLOADS_DIR="/home/ga/Downloads"
if [ -d "$DOWNLOADS_DIR" ]; then
    echo "Contents of Downloads folder:"
    ls -lah "$DOWNLOADS_DIR" || true
    
    # Look for the expected image file
    if ls "$DOWNLOADS_DIR"/*climate*infographic*.png 2>/dev/null | head -1; then
        FOUND_IMAGE=$(ls "$DOWNLOADS_DIR"/*climate*infographic*.png 2>/dev/null | head -1)
        echo "✓ Found climate infographic: $FOUND_IMAGE"
        # Copy to temp for easier verification
        cp "$FOUND_IMAGE" /tmp/downloaded_infographic.png 2>/dev/null || true
    elif ls "$DOWNLOADS_DIR"/*.png 2>/dev/null | head -1; then
        FOUND_IMAGE=$(ls -t "$DOWNLOADS_DIR"/*.png 2>/dev/null | head -1)
        echo "⚠ Found PNG image: $FOUND_IMAGE (checking if it's the infographic)"
        cp "$FOUND_IMAGE" /tmp/downloaded_infographic.png 2>/dev/null || true
    else
        echo "✗ No image files found in Downloads"
    fi
else
    echo "✗ Downloads folder not found"
fi

# Create a summary file for verification
cat > /tmp/task_export_summary.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "tab_count": $TAB_COUNT,
    "bookmarks_exported": $BOOKMARKS_EXPORTED,
    "history_exported": $HISTORY_EXPORTED,
    "downloads_folder": "$DOWNLOADS_DIR",
    "image_found": $([ -f /tmp/downloaded_infographic.png ] && echo "true" || echo "false")
}
EOF

echo "✅ Export complete"
echo "Summary:"
cat /tmp/task_export_summary.json