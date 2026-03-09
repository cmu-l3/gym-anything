#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Bookmarklet Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/bookmarklet_verification"
mkdir -p "$VERIFY_DIR"

# Capture screenshot BEFORE closing Chrome (to see if background is red)
echo "Capturing screenshot of current page state..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/page_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved: $VERIFY_DIR/page_screenshot.png"
fi

# Capture active tab information via CDP
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_TAB=$(jq '[.[] | select(.type == "page")][0]' /tmp/chrome_tabs.json)
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    
    # Try to get body background color via CDP Runtime.evaluate if possible
    # Note: This requires WebSocket connection, which is complex
    # We'll rely on screenshot analysis instead
fi

# Try to capture body background color using CDP (simplified attempt)
echo "Attempting to capture background color via CDP..."
if command -v python3 &> /dev/null; then
    python3 - <<'PYEOF' > "$VERIFY_DIR/bg_color.txt" 2>/dev/null || true
import json
import requests
import sys

try:
    # Get the first page tab
    resp = requests.get('http://localhost:9222/json', timeout=2)
    tabs = resp.json()
    page_tabs = [t for t in tabs if t.get('type') == 'page']
    
    if page_tabs:
        # For now, just save tab info
        # Full CDP WebSocket implementation would be needed for Runtime.evaluate
        print("CDP accessible")
    else:
        print("No page tabs found")
except Exception as e:
    print(f"CDP error: {e}")
    sys.exit(1)
PYEOF
fi

# Gracefully close Chrome to ensure bookmarks are persisted to disk
echo "Closing Chrome to save bookmarks..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export bookmarks file for verification
echo "Exporting Chrome bookmarks..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Bookmarks" ]; then
    cp "$CHROME_PROFILE/Bookmarks" "$VERIFY_DIR/bookmarks.json"
    echo "✓ Bookmarks exported to $VERIFY_DIR/bookmarks.json"
    
    # Quick check for javascript: bookmarks
    if grep -q "javascript:" "$VERIFY_DIR/bookmarks.json" 2>/dev/null; then
        echo "✓ JavaScript bookmark detected in file"
    else
        echo "⚠ No JavaScript bookmark detected in file"
    fi
else
    echo "⚠ Warning: Bookmarks file not found at $CHROME_PROFILE/Bookmarks"
    # Try alternative locations
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Bookmarks" ]; then
        cp "$ALT_PROFILE/Bookmarks" "$VERIFY_DIR/bookmarks.json"
        echo "✓ Bookmarks exported from alternative location"
    else
        echo "✗ Could not find Bookmarks file in any known location"
    fi
fi

# Copy all verification files to /tmp for easy access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files in: $VERIFY_DIR"
ls -lh "$VERIFY_DIR" 2>/dev/null || true