#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Browsing History Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    echo "$ACTIVE_TITLE" > /tmp/final_title.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure databases are synced to disk
echo "Closing Chrome to save database changes..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Wait for file system sync
sync
sleep 1

# Export Chrome History and Cookies databases for verification
echo "Exporting Chrome databases for verification..."

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    echo "✓ Found History at primary location"
    cp "$CHROME_PROFILE/History" /tmp/history_export.db
    echo "  Copied to: /tmp/history_export.db"
    
    # Show history entry count for debugging
    HISTORY_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "error")
    echo "  History entry count: $HISTORY_COUNT"
else
    echo "⚠ History not found at primary location, trying alternative..."
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/History" ]; then
        echo "✓ Found History at alternative location"
        cp "$ALT_PROFILE/History" /tmp/history_export.db
        HISTORY_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "error")
        echo "  History entry count: $HISTORY_COUNT"
    else
        echo "✗ Could not find History database"
        touch /tmp/history_export.db  # Create empty file to prevent copy errors
    fi
fi

# Export Cookies database (should be preserved)
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    echo "✓ Found Cookies at primary location"
    cp "$CHROME_PROFILE/Cookies" /tmp/cookies_export.db
    echo "  Copied to: /tmp/cookies_export.db"
    
    # Show cookie count for debugging
    COOKIE_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "error")
    echo "  Cookie count: $COOKIE_COUNT"
elif [ -f "$ALT_PROFILE/Cookies" ]; then
    echo "✓ Found Cookies at alternative location"
    cp "$ALT_PROFILE/Cookies" /tmp/cookies_export.db
    COOKIE_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "error")
    echo "  Cookie count: $COOKIE_COUNT"
else
    echo "⚠ Could not find Cookies database"
    touch /tmp/cookies_export.db
fi

# Copy baseline URLs file for verification
if [ -f "/tmp/history_task_data/baseline_urls.txt" ]; then
    cp /tmp/history_task_data/baseline_urls.txt /tmp/baseline_urls_export.txt
    echo "✓ Baseline URLs exported"
else
    echo "⚠ Baseline URLs file not found"
    touch /tmp/baseline_urls_export.txt
fi

echo "✅ Export complete"
echo "Files exported to /tmp/ for verification:"
echo "  - history_export.db (History database)"
echo "  - cookies_export.db (Cookies database)"
echo "  - baseline_urls_export.txt (Baseline URLs)"
echo "  - final_screenshot.png (Screenshot)"