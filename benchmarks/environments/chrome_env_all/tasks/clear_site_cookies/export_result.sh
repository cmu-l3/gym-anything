#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Cookie Deletion Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window to ensure any pending operations complete
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/cookie_task_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/cookie_task_screenshot.png"
fi

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Close Chrome gracefully to ensure Cookies database is written to disk
echo "Closing Chrome to save cookies database..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Verify Chrome is fully closed
CHROME_RUNNING=$(pgrep -f "chrome" | wc -l || echo "0")
echo "Chrome processes remaining: $CHROME_RUNNING"

# Export Cookies database to temporary location for verification
echo "Exporting Chrome Cookies database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
COOKIES_DB="$CHROME_PROFILE/Cookies"

if [ -f "$COOKIES_DB" ]; then
    # Copy Cookies database
    cp "$COOKIES_DB" /tmp/chrome_cookies.db
    echo "✓ Cookies database exported to /tmp/chrome_cookies.db"
    
    # Get file size for verification
    COOKIES_SIZE=$(stat -c%s "$COOKIES_DB")
    echo "✓ Cookies database size: $COOKIES_SIZE bytes"
    
    # Quick check: count cookies for debugging
    if command -v sqlite3 &> /dev/null; then
        HTTPBIN_COUNT=$(sqlite3 "$COOKIES_DB" "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%httpbin.org%';" 2>/dev/null || echo "error")
        TOTAL_COUNT=$(sqlite3 "$COOKIES_DB" "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "error")
        echo "Debug info: httpbin.org cookies = $HTTPBIN_COUNT, total cookies = $TOTAL_COUNT"
        
        # Save counts to temp file for verifier
        echo "$HTTPBIN_COUNT" > /tmp/httpbin_cookie_count.txt
        echo "$TOTAL_COUNT" > /tmp/total_cookie_count.txt
    fi
else
    echo "⚠ Warning: Cookies database not found at $COOKIES_DB"
    
    # Try alternative profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    ALT_COOKIES="$ALT_PROFILE/Cookies"
    
    if [ -f "$ALT_COOKIES" ]; then
        cp "$ALT_COOKIES" /tmp/chrome_cookies.db
        echo "✓ Cookies database exported from alternative location"
    else
        echo "✗ Could not find Cookies database in any known location"
        touch /tmp/chrome_cookies.db  # Create empty file to prevent verification errors
    fi
fi

echo "✅ Export complete"