#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Cookie Management Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
echo "Focusing Chrome window..."
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
echo "Taking final screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
else
    echo "⚠ Warning: Could not capture CDP information"
fi

# Gracefully close Chrome to ensure cookies are persisted to disk
echo "Closing Chrome to flush cookies database..."
# First try graceful shutdown
pkill -SIGTERM chrome || true
sleep 3

# Check if Chrome is still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, waiting longer..."
    sleep 2
fi

# If still running, force kill
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    pkill -9 -f "chrome" || true
    sleep 1
fi

echo "✓ Chrome closed"

# Give filesystem time to sync
sync
sleep 1

# Export cookies database to temporary location for verification
echo "Exporting Chrome Cookies database..."
CHROME_PROFILE_CDP="/home/ga/.config/google-chrome-cdp/Default"
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"

# Try both possible locations
COOKIES_EXPORTED=false

if [ -f "$CHROME_PROFILE_CDP/Cookies" ]; then
    echo "Found Cookies at: $CHROME_PROFILE_CDP/Cookies"
    cp "$CHROME_PROFILE_CDP/Cookies" /tmp/cookies_export.db
    COOKIES_EXPORTED=true
    echo "✓ Cookies exported from CDP profile"
elif [ -f "$CHROME_PROFILE/Cookies" ]; then
    echo "Found Cookies at: $CHROME_PROFILE/Cookies"
    cp "$CHROME_PROFILE/Cookies" /tmp/cookies_export.db
    COOKIES_EXPORTED=true
    echo "✓ Cookies exported from default profile"
else
    echo "⚠ Warning: Cookies database not found in either location:"
    echo "  - $CHROME_PROFILE_CDP/Cookies"
    echo "  - $CHROME_PROFILE/Cookies"
    touch /tmp/cookies_export.db  # Create empty file to prevent errors
fi

# Verify the exported database is valid
if [ -f /tmp/cookies_export.db ] && [ -s /tmp/cookies_export.db ]; then
    if command -v sqlite3 &> /dev/null; then
        # Try to query the database to verify it's valid
        if sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies;" > /tmp/cookie_count.txt 2>&1; then
            COOKIE_COUNT=$(cat /tmp/cookie_count.txt)
            echo "✓ Cookies database is valid, contains $COOKIE_COUNT cookies"
            
            # Log domain-specific counts for debugging
            echo "Domain-specific cookie counts:"
            GITHUB_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%github.com%';" 2>/dev/null || echo "0")
            EXAMPLE_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%example.com%';" 2>/dev/null || echo "0")
            WIKI_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%wikipedia.org%';" 2>/dev/null || echo "0")
            
            echo "  github.com: $GITHUB_COUNT cookies (should be 0 after task)"
            echo "  example.com: $EXAMPLE_COUNT cookies (should be > 0)"
            echo "  wikipedia.org: $WIKI_COUNT cookies (should be > 0)"
            
            # Save counts for verifier
            cat > /tmp/cookie_counts.txt << EOF
github=$GITHUB_COUNT
example=$EXAMPLE_COUNT
wikipedia=$WIKI_COUNT
total=$COOKIE_COUNT
EOF
        else
            echo "⚠ Warning: Cookies database exists but may be corrupted"
            echo "SQLite error: $(cat /tmp/cookie_count.txt)"
        fi
    else
        echo "⚠ Warning: sqlite3 not available for validation"
    fi
else
    echo "⚠ Warning: Exported cookies database is empty or missing"
fi

# Set proper permissions for copied files
chmod 644 /tmp/cookies_export.db 2>/dev/null || true
chmod 644 /tmp/cookie_counts.txt 2>/dev/null || true
chmod 644 /tmp/final_url.txt 2>/dev/null || true
chmod 644 /tmp/final_screenshot.png 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files prepared in /tmp/"