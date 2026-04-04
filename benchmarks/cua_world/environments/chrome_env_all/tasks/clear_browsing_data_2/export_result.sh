#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Browsing Data Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Wait a moment for any pending operations
sleep 2

# Close Chrome to ensure all data is flushed to disk
echo "Closing Chrome to flush data..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 3

# Verify Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Warning: Chrome still running, forcing kill..."
    pkill -9 -f "chrome.*remote-debugging-port" || true
    sleep 2
fi

# Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
HISTORY_DB="${CHROME_PROFILE}/History"
COOKIES_DB="${CHROME_PROFILE}/Cookies"

# Copy the "after" state for verification
echo "Copying Chrome data files for verification..."

if [ -f "${HISTORY_DB}" ]; then
    cp "${HISTORY_DB}" /tmp/history_after.db
    chown ga:ga /tmp/history_after.db
    echo "✓ History database copied"
else
    echo "⚠ Warning: History database not found"
fi

if [ -f "${COOKIES_DB}" ]; then
    cp "${COOKIES_DB}" /tmp/cookies_after.db
    chown ga:ga /tmp/cookies_after.db
    echo "✓ Cookies database copied"
else
    echo "⚠ Warning: Cookies database not found"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Quick diagnostic: show history entry counts
if [ -f /tmp/history_before.db ] && [ -f /tmp/history_after.db ]; then
    BEFORE_COUNT=$(sqlite3 /tmp/history_before.db "SELECT COUNT(*) FROM urls WHERE id >= 100001;" 2>/dev/null || echo "0")
    AFTER_COUNT=$(sqlite3 /tmp/history_after.db "SELECT COUNT(*) FROM urls WHERE id >= 100001;" 2>/dev/null || echo "0")
    echo "History entries: ${BEFORE_COUNT} before → ${AFTER_COUNT} after"
fi

echo "✅ Export complete"