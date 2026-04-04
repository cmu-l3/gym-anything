#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Recently Closed Tabs Recovery Task Export: recently_closed_recovery@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture all tabs via CDP BEFORE closing Chrome
echo "Capturing all tabs information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_all_tabs_recovery.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs (not background pages, extensions, etc.)
    jq '[.[] | select(.type == "page")]' /tmp/chrome_all_tabs_recovery.json > /tmp/chrome_page_tabs_recovery.json
    
    TAB_COUNT=$(jq 'length' /tmp/chrome_page_tabs_recovery.json)
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for easy debugging
    jq -r '.[] | "\(.url)|\(.title)"' /tmp/chrome_page_tabs_recovery.json > /tmp/tab_list_recovery.txt
    
    echo "Current tab information:"
    cat /tmp/tab_list_recovery.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > /tmp/chrome_page_tabs_recovery.json
    touch /tmp/tab_list_recovery.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_recovery.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_recovery.png"
fi

# Gracefully close Chrome to ensure History database is properly closed
echo "Closing Chrome to ensure History is saved..."
pkill -TERM chrome 2>/dev/null || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    pkill -9 -f "chrome" || true
    sleep 1
fi

# Export History database to temporary location for verification
echo "Exporting Chrome History database..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

HISTORY_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/History" ]; then
        # Copy History database
        cp "$CHROME_PROFILE/History" /tmp/chrome_history_recovery.db
        echo "✓ History exported from: $CHROME_PROFILE/History"
        
        # Verify it's a valid SQLite database
        if sqlite3 /tmp/chrome_history_recovery.db "SELECT COUNT(*) FROM urls;" > /dev/null 2>&1; then
            URL_COUNT=$(sqlite3 /tmp/chrome_history_recovery.db "SELECT COUNT(*) FROM urls;")
            echo "✓ History database valid with $URL_COUNT total URL entries"
            HISTORY_EXPORTED=true
            break
        else
            echo "⚠ Warning: History database from $CHROME_PROFILE appears corrupted"
        fi
    fi
done

if [ "$HISTORY_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find or export valid History database"
    # Create empty database to prevent verification errors
    touch /tmp/chrome_history_recovery.db
fi

# Also capture bookmarks for additional context (optional)
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
        cp "$CHROME_PROFILE/Bookmarks" /tmp/chrome_bookmarks_recovery.json 2>/dev/null || true
        break
    fi
done

echo "✅ Export complete"
echo "Verification files available:"
echo "  - /tmp/chrome_page_tabs_recovery.json (CDP tab list)"
echo "  - /tmp/chrome_history_recovery.db (History database)"
echo "  - /tmp/tab_list_recovery.txt (Human-readable tab list)"
echo "  - /tmp/final_screenshot_recovery.png (Screenshot)"