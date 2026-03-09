#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome IndexedDB Modification Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure latest state is committed
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/indexeddb_verification"
mkdir -p "$VERIFY_DIR"

# Capture CDP information about active tab
echo "Capturing Chrome tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Extract active tab details
    ACTIVE_TAB=$(jq '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_tabs.json")
    echo "$ACTIVE_TAB" > "$VERIFY_DIR/active_tab.json"
    
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    WS_URL=$(echo "$ACTIVE_TAB" | jq -r '.webSocketDebuggerUrl // ""')
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    # Save WebSocket URL for verifier
    echo "$WS_URL" > "$VERIFY_DIR/websocket_url.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/websocket_url.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Create a marker file indicating export completed
date > "$VERIFY_DIR/export_completed.txt"

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"