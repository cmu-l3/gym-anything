#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Offline Mode Simulation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick sqlite3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create export directory
EXPORT_DIR="/tmp/offline_verification"
mkdir -p "$EXPORT_DIR"

# Capture final state via CDP
echo "Capturing final Chrome state via CDP..."
if curl -s http://localhost:9222/json > "$EXPORT_DIR/final_tabs.json" 2>/dev/null; then
    echo "✓ CDP data captured"
    
    # Extract active tab URL
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$EXPORT_DIR/final_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$EXPORT_DIR/final_url.txt"
    
    # Extract active tab title
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$EXPORT_DIR/final_tabs.json")
    echo "Active title: $ACTIVE_TITLE"
    echo "$ACTIVE_TITLE" > "$EXPORT_DIR/final_title.txt"
else
    echo "⚠ Warning: CDP query failed"
    echo "" > "$EXPORT_DIR/final_url.txt"
    echo "" > "$EXPORT_DIR/final_title.txt"
fi

# Take final screenshot
echo "Capturing final screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $EXPORT_DIR/final_screenshot.png" 2>/dev/null || true
    if [ -f "$EXPORT_DIR/final_screenshot.png" ]; then
        echo "✓ Screenshot saved"
        ls -lh "$EXPORT_DIR/final_screenshot.png"
    fi
fi

# Check if any screenshots were taken during task
TASK_SCREENSHOTS="/tmp/offline_task_screenshots"
if [ -d "$TASK_SCREENSHOTS" ] && [ "$(ls -A $TASK_SCREENSHOTS 2>/dev/null)" ]; then
    echo "Found task screenshots, copying..."
    cp -r "$TASK_SCREENSHOTS"/* "$EXPORT_DIR/" 2>/dev/null || true
    SCREENSHOT_COUNT=$(ls -1 "$TASK_SCREENSHOTS" 2>/dev/null | wc -l)
    echo "✓ Copied $SCREENSHOT_COUNT screenshot(s) from task execution"
fi

# Export browser history for offline navigation attempt detection
echo "Exporting browser history..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/History" ]; then
    # Make a copy of the History database
    cp "$CHROME_PROFILE/History" "$EXPORT_DIR/History.db" 2>/dev/null || true
    echo "✓ History database exported"
else
    echo "⚠ Warning: History database not found"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/History" ]; then
        cp "$ALT_PROFILE/History" "$EXPORT_DIR/History.db" 2>/dev/null || true
        echo "✓ History exported from alternative location"
    fi
fi

# Check for Chrome error pages in recent history
if command -v sqlite3 &> /dev/null && [ -f "$EXPORT_DIR/History.db" ]; then
    echo "Checking for error pages in history..."
    sqlite3 "$EXPORT_DIR/History.db" "SELECT url FROM urls WHERE url LIKE '%chrome-error%' OR url LIKE '%ERR_%' ORDER BY last_visit_time DESC LIMIT 5;" > "$EXPORT_DIR/error_urls.txt" 2>/dev/null || true
    if [ -s "$EXPORT_DIR/error_urls.txt" ]; then
        echo "✓ Found error page entries in history"
        cat "$EXPORT_DIR/error_urls.txt"
    fi
fi

# Copy everything to standard temp location
cp -r "$EXPORT_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files at: $EXPORT_DIR"