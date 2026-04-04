#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Console Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/devtools_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing final page state via CDP..."

# Get active tab information
if curl -s http://localhost:9222/json > "$VERIFY_DIR/final_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Extract WebSocket debugger URL for the active tab
    WS_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/final_tabs.json")
    
    if [ -n "$WS_URL" ] && [ "$WS_URL" != "null" ]; then
        echo "Active tab WebSocket URL: $WS_URL"
        echo "$WS_URL" > "$VERIFY_DIR/ws_debugger_url.txt"
    fi
    
    # Extract active URL and title
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/final_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/final_tabs.json")
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    # Create empty files to prevent verification errors
    echo "[]" > "$VERIFY_DIR/final_tabs.json"
    echo "" > "$VERIFY_DIR/ws_debugger_url.txt"
fi

# Take a final screenshot for debugging
echo "Capturing screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    
    if [ -f "$VERIFY_DIR/final_screenshot.png" ]; then
        echo "✓ Screenshot saved: $(ls -lh $VERIFY_DIR/final_screenshot.png | awk '{print $5}')"
    fi
fi

# Copy verification data to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"