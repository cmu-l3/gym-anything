#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Autofill Profile Setup Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
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

# CRITICAL: Close Chrome gracefully to ensure database writes are flushed
echo "Closing Chrome to ensure autofill data is saved to database..."
pkill -TERM chrome || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "chrome" || true
    sleep 2
fi

echo "✓ Chrome closed"

# Export Web Data SQLite database (contains autofill profiles)
echo "Exporting Chrome Web Data database..."

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
WEB_DATA_PATH="$CHROME_PROFILE/Web Data"

if [ -f "$WEB_DATA_PATH" ]; then
    echo "Found Web Data at: $WEB_DATA_PATH"
    cp "$WEB_DATA_PATH" /tmp/web_data_export.db
    echo "✓ Web Data exported to /tmp/web_data_export.db"
    ls -lh /tmp/web_data_export.db
else
    echo "⚠ Warning: Web Data not found at $WEB_DATA_PATH"
    # Try alternative location
    CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"
    WEB_DATA_PATH_ALT="$CHROME_PROFILE_ALT/Web Data"
    
    if [ -f "$WEB_DATA_PATH_ALT" ]; then
        echo "Found Web Data at alternative location: $WEB_DATA_PATH_ALT"
        cp "$WEB_DATA_PATH_ALT" /tmp/web_data_export.db
        echo "✓ Web Data exported from alternative location"
        ls -lh /tmp/web_data_export.db
    else
        echo "✗ Could not find Web Data database in any known location"
        # Create marker file to indicate failure
        echo "not_found" > /tmp/web_data_export.db
    fi
fi

# Also export Preferences for additional verification
echo "Exporting Chrome Preferences..."
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported"
elif [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
    cp "$CHROME_PROFILE_ALT/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported from alternative location"
fi

# Quick database inspection for debugging
if [ -f /tmp/web_data_export.db ] && [ "$(stat -c%s /tmp/web_data_export.db)" -gt 100 ]; then
    echo "Database structure check:"
    sqlite3 /tmp/web_data_export.db ".tables" 2>/dev/null || echo "Could not query database tables"
    
    # Count autofill profiles
    PROFILE_COUNT=$(sqlite3 /tmp/web_data_export.db "SELECT COUNT(*) FROM autofill_profiles;" 2>/dev/null || echo "0")
    echo "Autofill profiles in database: $PROFILE_COUNT"
fi

echo "✅ Export complete"