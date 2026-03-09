#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Cache Fix Task Export: clear_cache_fix@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
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

# Gracefully close Chrome to ensure all data is persisted to disk
echo "Closing Chrome to persist data changes..."
pkill chrome || true
sleep 3

# Force close if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 chrome || true
    sleep 2
fi

# Export Cookies database to temporary location for verification
echo "Exporting Chrome Cookies database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Cookies" ]; then
    cp "$CHROME_PROFILE/Cookies" /tmp/chrome_cookies_export.db
    echo "✓ Cookies exported to /tmp/chrome_cookies_export.db"
    
    # Display cookie counts for debugging
    TOTAL_COOKIES=$(sqlite3 /tmp/chrome_cookies_export.db "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "0")
    TARGET_COOKIES=$(sqlite3 /tmp/chrome_cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%example-site.com%';" 2>/dev/null || echo "0")
    
    echo "Total cookies remaining: $TOTAL_COOKIES"
    echo "Target site cookies: $TARGET_COOKIES (should be 0)"
    
    # List all unique domains for debugging
    echo "Domains with cookies:"
    sqlite3 /tmp/chrome_cookies_export.db "SELECT DISTINCT host_key FROM cookies;" 2>/dev/null | head -10 || true
else
    echo "⚠ Warning: Cookies database not found at $CHROME_PROFILE/Cookies"
    
    # Try alternative location
    CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE_ALT/Cookies" ]; then
        cp "$CHROME_PROFILE_ALT/Cookies" /tmp/chrome_cookies_export.db
        echo "✓ Cookies exported from alternative location"
    else
        echo "✗ Could not find Cookies database"
        # Create empty file to prevent verification errors
        touch /tmp/chrome_cookies_export.db
    fi
fi

# Also copy Preferences for method validation
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported"
fi

echo "✅ Export complete"
echo "Verification will check that example-site.com data was cleared selectively"