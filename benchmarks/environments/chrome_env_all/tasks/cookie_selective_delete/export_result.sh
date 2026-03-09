#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Cookie Selective Deletion Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

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

# Gracefully close Chrome to ensure cookies are persisted to disk
echo "Closing Chrome to save cookie changes..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Wait a bit more to ensure database is unlocked
sleep 1

# Export Cookies database to temporary location for verification
echo "Exporting Chrome Cookies database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
COOKIES_DB="$CHROME_PROFILE/Cookies"

if [ -f "$COOKIES_DB" ]; then
    # Copy to /tmp for verifier access
    cp "$COOKIES_DB" /tmp/cookies_final.db
    echo "✓ Cookies database exported to /tmp/cookies_final.db"
    
    # Also try alternative location
    chmod 644 /tmp/cookies_final.db 2>/dev/null || true
    
    # Quick check of cookie count for debugging
    COOKIE_COUNT=$(sqlite3 /tmp/cookies_final.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%httpbin.org%';" 2>/dev/null || echo "unknown")
    echo "Final httpbin.org cookie count: $COOKIE_COUNT"
    
    # List cookies for debugging
    echo "Cookies for httpbin.org:"
    sqlite3 /tmp/cookies_final.db "SELECT name, value FROM cookies WHERE host_key LIKE '%httpbin.org%';" 2>/dev/null || echo "Could not query cookies"
    
else
    echo "⚠ Warning: Cookies database not found at $COOKIES_DB"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    ALT_COOKIES="$ALT_PROFILE/Cookies"
    
    if [ -f "$ALT_COOKIES" ]; then
        cp "$ALT_COOKIES" /tmp/cookies_final.db
        chmod 644 /tmp/cookies_final.db 2>/dev/null || true
        echo "✓ Cookies database exported from alternative location"
    else
        echo "✗ Could not find Cookies database in any location"
        # Create empty file to prevent verifier errors
        touch /tmp/cookies_final.db
    fi
fi

# Export the initial cookies snapshot as well for comparison
if [ -f "/tmp/cookies_initial.db" ]; then
    echo "✓ Initial cookies snapshot available for comparison"
else
    echo "⚠ Initial cookies snapshot not found"
fi

echo "✅ Export complete"
echo "Cookie database ready for verification at /tmp/cookies_final.db"