#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Find in Page Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 python3-pip || true
pip3 install -q requests 2>/dev/null || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/find_in_page_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab information via CDP
echo "Capturing active tab state via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    WS_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/chrome_tabs.json")
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
    echo "$WS_URL" > "$VERIFY_DIR/websocket_url.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
fi

# Capture scroll position using CDP Runtime.evaluate
echo "Capturing page state via CDP..."
python3 - <<'PYTHON_EOF' > "$VERIFY_DIR/page_state.json" 2>/dev/null || true
import json
import requests
import sys

try:
    # Get active tab
    tabs_response = requests.get('http://localhost:9222/json', timeout=5)
    tabs = tabs_response.json()
    
    if not tabs:
        print(json.dumps({"error": "No tabs found"}))
        sys.exit(1)
    
    active_tab = [t for t in tabs if t.get('type') == 'page'][0]
    ws_url = active_tab.get('webSocketDebuggerUrl', '')
    tab_id = active_tab.get('id', '')
    
    # Save basic info
    state = {
        "url": active_tab.get('url', ''),
        "title": active_tab.get('title', ''),
        "tab_id": tab_id,
        "ws_url": ws_url,
        "error": None
    }
    
    print(json.dumps(state, indent=2))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
PYTHON_EOF

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Copy all verification files to standard location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification data saved to: $VERIFY_DIR"