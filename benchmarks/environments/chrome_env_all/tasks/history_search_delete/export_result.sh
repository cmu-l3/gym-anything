#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Search and Selective Deletion Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window to ensure it's active
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" 2>/dev/null || true
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

# Close Chrome gracefully to ensure history is written to disk
echo "Closing Chrome to save history..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
if pgrep -f "google-chrome" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" 2>/dev/null || true
    sleep 1
fi

# Export History database for verification
echo "Exporting Chrome History database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

HISTORY_EXPORTED=false

# Try primary location
if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/history_export.db
    echo "✓ History exported from: $CHROME_PROFILE/History"
    HISTORY_EXPORTED=true
elif [ -f "$ALT_PROFILE/History" ]; then
    cp "$ALT_PROFILE/History" /tmp/history_export.db
    echo "✓ History exported from: $ALT_PROFILE/History"
    HISTORY_EXPORTED=true
else
    echo "⚠ Warning: History database not found"
fi

# If history was exported, analyze it
if [ "$HISTORY_EXPORTED" = true ]; then
    echo "Analyzing final history state..."
    
    FINAL_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
    SHOPPING_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%shopping-site%';" 2>/dev/null || echo "0")
    NEWS_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%news-website%';" 2>/dev/null || echo "0")
    WORK_COUNT=$(sqlite3 /tmp/history_export.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%work-related%';" 2>/dev/null || echo "0")
    
    echo "Final history state:"
    echo "  Total URLs: $FINAL_COUNT"
    echo "  Shopping URLs: $SHOPPING_COUNT (should be 0)"
    echo "  News URLs: $NEWS_COUNT (should be 2)"
    echo "  Work URLs: $WORK_COUNT (should be 2)"
    
    # Save final state for verifier
    cat > /tmp/final_history_state.json << EOF
{
    "total_count": $FINAL_COUNT,
    "shopping_count": $SHOPPING_COUNT,
    "news_count": $NEWS_COUNT,
    "work_count": $WORK_COUNT
}
EOF
fi

# Export sample URLs for debugging
if [ "$HISTORY_EXPORTED" = true ]; then
    echo "Sample URLs in history:"
    sqlite3 /tmp/history_export.db "SELECT url FROM urls LIMIT 20;" 2>/dev/null | head -10 || true
fi

echo "✅ Export complete"