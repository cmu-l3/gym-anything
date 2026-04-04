#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective Cookie Cleanup Task Export ==="

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

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Gracefully close Chrome to ensure cookies are persisted to disk
echo "Closing Chrome to save cookie changes..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Cookies database to temporary location for verification
echo "Exporting Chrome Cookies database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
COOKIES_DB="$CHROME_PROFILE/Cookies"

if [ -f "$COOKIES_DB" ]; then
    # Copy the cookies database
    cp "$COOKIES_DB" /tmp/cookies_export.db
    echo "✓ Cookies database exported to /tmp/cookies_export.db"
    
    # Get cookie count for quick check
    FINAL_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "0")
    echo "  Final cookie count: $FINAL_COUNT"
    
    # Get count by trusted domains
    GMAIL_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%gmail.com%';" 2>/dev/null || echo "0")
    COMPANY_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%company-dashboard.example.com%';" 2>/dev/null || echo "0")
    BANK_COUNT=$(sqlite3 /tmp/cookies_export.db "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%secure-bank.example.com%';" 2>/dev/null || echo "0")
    
    echo "  Trusted domain cookies:"
    echo "    gmail.com: $GMAIL_COUNT"
    echo "    company-dashboard.example.com: $COMPANY_COUNT"
    echo "    secure-bank.example.com: $BANK_COUNT"
    
else
    echo "⚠ Warning: Cookies database not found at $COOKIES_DB"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    ALT_COOKIES="$ALT_PROFILE/Cookies"
    if [ -f "$ALT_COOKIES" ]; then
        cp "$ALT_COOKIES" /tmp/cookies_export.db
        echo "✓ Cookies database exported from alternative location"
    else
        echo "✗ Could not find Cookies database"
        touch /tmp/cookies_export.db  # Create empty file to avoid errors
    fi
fi

# Also copy the initial state for comparison
if [ -f "/tmp/initial_cookie_state.json" ]; then
    cp /tmp/initial_cookie_state.json /tmp/initial_cookie_state_export.json
    echo "✓ Initial state metadata preserved"
fi

echo "✅ Export complete"
echo "Verification will compare initial state with final cookie database"