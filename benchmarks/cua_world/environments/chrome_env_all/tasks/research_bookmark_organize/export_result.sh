#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Research Bookmark Organization Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure bookmarks are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab and all tabs via CDP for additional verification
echo "Capturing tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_final_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_final_tabs.json)
    TAB_COUNT=$(jq '[.[] | select(.type == "page")] | length' /tmp/chrome_final_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Total tabs: $TAB_COUNT"
    
    # Extract all URLs for debugging
    jq -r '.[] | select(.type == "page") | .url' /tmp/chrome_final_tabs.json > /tmp/final_tabs_urls.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_bookmarks.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_bookmarks.png"
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
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

BOOKMARKS_EXPORTED=false

for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_export.json
        echo "✓ Bookmarks exported from: $CHROME_PROFILE/Bookmarks"
        
        # Also create a backup for debugging
        cp "$CHROME_PROFILE/Bookmarks" /tmp/bookmarks_backup_$(date +%s).json
        
        # Show bookmark file size for validation
        ls -lh "$CHROME_PROFILE/Bookmarks"
        
        BOOKMARKS_EXPORTED=true
        break
    fi
done

if [ "$BOOKMARKS_EXPORTED" = false ]; then
    echo "⚠ Warning: Bookmarks file not found in any known location"
    echo "Checked locations:"
    for prof in "${CHROME_PROFILES[@]}"; do
        echo "  - $prof/Bookmarks"
    done
fi

# Export initial tab URLs for comparison
if [ -f /tmp/research_tabs_urls.txt ]; then
    cp /tmp/research_tabs_urls.txt /tmp/initial_tabs_comparison.txt
    echo "Initial tabs URLs copied for verification"
fi

echo "✅ Export complete"
echo "Verification files available:"
echo "  - /tmp/bookmarks_export.json (primary)"
echo "  - /tmp/chrome_final_tabs.json (tab state)"
echo "  - /tmp/final_screenshot_bookmarks.png (visual debug)"