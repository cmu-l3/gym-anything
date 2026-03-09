#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Password Manager Entry Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time to ensure any pending operations complete
echo "Focusing Chrome window..."
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
else
    echo "⚠ Warning: Could not capture CDP information"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# IMPORTANT: Gracefully close Chrome to ensure Login Data database is saved to disk
# Chrome may buffer password manager changes in memory
echo "Closing Chrome to save Login Data..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 2
fi

# Verify Chrome is stopped
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "✓ Chrome successfully stopped"
else
    echo "⚠ Warning: Chrome may still be running"
fi

# Export Login Data database to temporary location for verification
echo "Exporting Chrome Login Data database..."

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
LOGIN_DATA="$CHROME_PROFILE/Login Data"

if [ -f "$LOGIN_DATA" ]; then
    # Make a copy (cannot read directly if Chrome has locks)
    cp "$LOGIN_DATA" /tmp/login_data_export.db
    echo "✓ Login Data exported from: $LOGIN_DATA"
    ls -lh "$LOGIN_DATA"
else
    echo "⚠ Warning: Login Data not found at $LOGIN_DATA"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    ALT_LOGIN_DATA="$ALT_PROFILE/Login Data"
    
    if [ -f "$ALT_LOGIN_DATA" ]; then
        cp "$ALT_LOGIN_DATA" /tmp/login_data_export.db
        echo "✓ Login Data exported from alternative location: $ALT_LOGIN_DATA"
        ls -lh "$ALT_LOGIN_DATA"
    else
        echo "✗ Login Data database not found in any expected location"
        echo "Searched locations:"
        echo "  - $LOGIN_DATA"
        echo "  - $ALT_LOGIN_DATA"
        # Create empty marker file to prevent verification errors
        touch /tmp/login_data_export.db
    fi
fi

# Also copy the task start time for verification
if [ -f /tmp/task_start_time.txt ]; then
    cp /tmp/task_start_time.txt /tmp/task_start_time_export.txt
    echo "✓ Task start time exported"
else
    echo "⚠ Warning: Task start time not found, using current time"
    date +%s > /tmp/task_start_time_export.txt
fi

# Quick sanity check: Query the database to see if any entries exist
if [ -f /tmp/login_data_export.db ] && [ -s /tmp/login_data_export.db ]; then
    echo ""
    echo "Quick database check..."
    ENTRY_COUNT=$(sqlite3 /tmp/login_data_export.db "SELECT COUNT(*) FROM logins;" 2>/dev/null || echo "0")
    echo "Total password entries in database: $ENTRY_COUNT"
    
    # Check for our specific entry
    TARGET_COUNT=$(sqlite3 /tmp/login_data_export.db "SELECT COUNT(*) FROM logins WHERE origin_url LIKE '%example-testsite.com%' OR signon_realm LIKE '%example-testsite.com%';" 2>/dev/null || echo "0")
    if [ "$TARGET_COUNT" -gt 0 ]; then
        echo "✓ Found $TARGET_COUNT entry(ies) for example-testsite.com"
    else
        echo "⚠ No entries found for example-testsite.com"
    fi
else
    echo "⚠ Login Data database is empty or missing"
fi

echo ""
echo "✅ Export complete"
echo "Verification files ready in /tmp/"