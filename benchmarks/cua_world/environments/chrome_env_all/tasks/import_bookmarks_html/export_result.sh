#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Import Bookmarks Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export bookmarks file to temporary location for verification
echo "Exporting Chrome bookmarks..."

# Try multiple possible locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

BOOKMARKS_FOUND=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_after_import.json
        echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
        echo "$CHROME_PROFILE" > /tmp/bookmarks_profile_path.txt
        BOOKMARKS_FOUND=true
        
        # Show file size for debugging
        FILE_SIZE=$(stat -c%s "$CHROME_PROFILE/Bookmarks")
        echo "  Bookmarks file size: ${FILE_SIZE} bytes"
        break
    fi
done

if [ "$BOOKMARKS_FOUND" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any known location"
    echo "Searched locations:"
    for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
        echo "  - $CHROME_PROFILE/Bookmarks"
    done
    
    # Create empty bookmarks file to prevent verification errors
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_after_import.json
fi

# Also ensure the "before" backup exists
if [ ! -f "/tmp/bookmarks_before_import.json" ]; then
    echo "⚠ Warning: No 'before' bookmarks backup found"
    echo '{"roots":{"bookmark_bar":{"children":[]}}}' > /tmp/bookmarks_before_import.json
fi

# Copy the original HTML file to temp for verification reference
if [ -f "/home/ga/Downloads/bookmarks_to_import.html" ]; then
    cp "/home/ga/Downloads/bookmarks_to_import.html" /tmp/bookmarks_source.html
    echo "✓ Source HTML file copied for verification"
fi

echo "✅ Export complete"
echo ""
echo "Verification files prepared:"
echo "  - /tmp/bookmarks_before_import.json (baseline)"
echo "  - /tmp/bookmarks_after_import.json (result)"
echo "  - /tmp/bookmarks_source.html (expected content)"