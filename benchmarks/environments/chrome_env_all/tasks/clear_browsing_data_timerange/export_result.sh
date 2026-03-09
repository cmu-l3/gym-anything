#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Browsing Data Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# IMPORTANT: Close Chrome to ensure databases are flushed to disk
echo "Closing Chrome to save database changes..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Export Chrome data files for verification
echo "Exporting Chrome data files..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

# Export Cookies database
if [ -f "$CHROME_PROFILE/Cookies" ]; then
    cp "$CHROME_PROFILE/Cookies" /tmp/cookies_after.db
    echo "✓ Cookies database exported"
    
    # Quick check of cookie count
    COOKIE_COUNT=$(sqlite3 "$CHROME_PROFILE/Cookies" "SELECT COUNT(*) FROM cookies" 2>/dev/null || echo "unknown")
    echo "  Cookie count: $COOKIE_COUNT"
else
    echo "⚠ Warning: Cookies database not found"
fi

# Export History database
if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/history_after.db
    echo "✓ History database exported"
    
    # Quick check of history count
    HISTORY_COUNT=$(sqlite3 "$CHROME_PROFILE/History" "SELECT COUNT(*) FROM urls" 2>/dev/null || echo "unknown")
    echo "  History entry count: $HISTORY_COUNT"
else
    echo "⚠ Warning: History database not found"
fi

# Export Preferences for additional verification
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/preferences_after.json
    echo "✓ Preferences exported"
fi

# Record cache state
CACHE_DIR="$CHROME_PROFILE/Cache"
if [ -d "$CACHE_DIR" ]; then
    CACHE_SIZE=$(du -sb "$CACHE_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
    CACHE_FILE_COUNT=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l || echo "0")
    echo "  Cache size: $CACHE_SIZE bytes"
    echo "  Cache file count: $CACHE_FILE_COUNT"
    echo "$CACHE_SIZE" > /tmp/cache_size_after.txt
    echo "$CACHE_FILE_COUNT" > /tmp/cache_file_count_after.txt
else
    echo "  Cache directory not found or cleared"
    echo "0" > /tmp/cache_size_after.txt
    echo "0" > /tmp/cache_file_count_after.txt
fi

# Copy baseline to temp for easy access
if [ -f "/tmp/chrome_baseline.json" ]; then
    cp /tmp/chrome_baseline.json /tmp/baseline_export.json
    echo "✓ Baseline copied for verification"
fi

echo "✅ Export complete"
echo "Files available for verification:"
echo "  - /tmp/cookies_after.db"
echo "  - /tmp/history_after.db"
echo "  - /tmp/baseline_export.json"
echo "  - /tmp/cache_size_after.txt"
echo "  - /tmp/cache_file_count_after.txt"