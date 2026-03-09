#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Search and Recovery Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP
echo "Capturing final active tab URL..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_final.json)
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > /tmp/final_active_url.txt
    echo "$ACTIVE_TITLE" > /tmp/final_active_title.txt
    
    echo "✓ Successfully captured final URL and title"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > /tmp/final_active_url.txt
    echo "" > /tmp/final_active_title.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Close Chrome to ensure history is written to disk
echo "Closing Chrome to save final history state..."
pkill -f "google-chrome" || true
sleep 2

# Export history database for verification
echo "Exporting Chrome history database..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    cp "$CHROME_PROFILE/History" /tmp/chrome_history_export.db
    echo "✓ History database exported to /tmp/chrome_history_export.db"
else
    echo "⚠ Warning: History database not found at $CHROME_PROFILE/History"
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/History" ]; then
        cp "$CHROME_PROFILE/History" /tmp/chrome_history_export.db
        echo "✓ History database exported from alternative location"
    else
        echo "✗ Could not find History database"
        touch /tmp/chrome_history_export.db
    fi
fi

echo "✅ Export complete"