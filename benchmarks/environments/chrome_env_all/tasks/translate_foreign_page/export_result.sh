#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Translation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 python3-requests || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/translate_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab information via CDP
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Get active tab URL and title
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
    
    # Get WebSocket debugger URL for the active tab
    WS_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "$WS_URL" > "$VERIFY_DIR/ws_url.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/active_url.txt"
    echo "" > "$VERIFY_DIR/active_title.txt"
fi

# Create a Python script to extract page translation state via CDP
cat > "$VERIFY_DIR/extract_page_state.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import json
import sys
import requests

try:
    # Get active tab info from CDP
    response = requests.get('http://localhost:9222/json', timeout=5)
    tabs = response.json()
    
    # Find the active page tab
    page_tabs = [t for t in tabs if t.get('type') == 'page']
    if not page_tabs:
        print(json.dumps({"error": "No page tabs found"}))
        sys.exit(1)
    
    active_tab = page_tabs[0]
    ws_url = active_tab.get('webSocketDebuggerUrl', '')
    
    # For simplicity, we'll just return basic info
    # Full WebSocket CDP communication would require additional libraries
    result = {
        "url": active_tab.get('url', ''),
        "title": active_tab.get('title', ''),
        "ws_available": bool(ws_url)
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
PYTHON_EOF

chmod +x "$VERIFY_DIR/extract_page_state.py"

# Run the extraction script
echo "Extracting page state..."
python3 "$VERIFY_DIR/extract_page_state.py" > "$VERIFY_DIR/page_state.json" 2>/dev/null || true

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"
ls -la "$VERIFY_DIR" || true