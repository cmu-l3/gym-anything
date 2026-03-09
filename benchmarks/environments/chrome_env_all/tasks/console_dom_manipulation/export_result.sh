#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Console DOM Manipulation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/console_dom_verification"
mkdir -p "$VERIFY_DIR"

# Capture all tabs information via CDP
echo "Capturing Chrome tabs via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Extract the test page tab
    jq '[.[] | select(.type == "page" and (.url | contains("devtools_test_page")))]' \
        "$VERIFY_DIR/chrome_tabs.json" > "$VERIFY_DIR/test_page_tab.json" || true
    
    # Get the WebSocket debugger URL for the test page
    WS_URL=$(jq -r '.[0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/test_page_tab.json")
    
    if [ -n "$WS_URL" ] && [ "$WS_URL" != "null" ]; then
        echo "✓ Found test page WebSocket URL: $WS_URL"
        echo "$WS_URL" > "$VERIFY_DIR/ws_debugger_url.txt"
    else
        echo "⚠ Warning: Could not find WebSocket URL for test page"
    fi
    
    # Get active tab URL and title
    ACTIVE_URL=$(jq -r '.[0].url // ""' "$VERIFY_DIR/test_page_tab.json")
    ACTIVE_TITLE=$(jq -r '.[0].title // ""' "$VERIFY_DIR/test_page_tab.json")
    
    echo "Active page URL: $ACTIVE_URL"
    echo "Active page title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > "$VERIFY_DIR/chrome_tabs.json"
    echo "" > "$VERIFY_DIR/ws_debugger_url.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"