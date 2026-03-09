#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Geolocation Sensors Override Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/geolocation_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing Chrome DevTools Protocol information..."

# Capture all tabs via CDP
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Extract active tab information
    jq -r '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_tabs.json" > "$VERIFY_DIR/active_tab.json" 2>/dev/null || echo "{}" > "$VERIFY_DIR/active_tab.json"
    
    ACTIVE_URL=$(jq -r '.url // ""' "$VERIFY_DIR/active_tab.json" 2>/dev/null || echo "")
    ACTIVE_TITLE=$(jq -r '.title // ""' "$VERIFY_DIR/active_tab.json" 2>/dev/null || echo "")
    WS_URL=$(jq -r '.webSocketDebuggerUrl // ""' "$VERIFY_DIR/active_tab.json" 2>/dev/null || echo "")
    
    echo "Active tab URL: $ACTIVE_URL"
    echo "Active tab title: $ACTIVE_TITLE"
    echo "$WS_URL" > "$VERIFY_DIR/ws_debugger_url.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "{}" > "$VERIFY_DIR/chrome_tabs.json"
    echo "" > "$VERIFY_DIR/ws_debugger_url.txt"
fi

# Create a Python script to query geolocation via CDP Runtime.evaluate
cat > "$VERIFY_DIR/query_geolocation.py" << 'PYTHON_EOF'
#!/usr/bin/env python3
import json
import sys

try:
    import requests
    
    # Query CDP for tabs
    response = requests.get('http://localhost:9222/json', timeout=5)
    tabs = response.json()
    
    # Find page tab
    page_tab = None
    for tab in tabs:
        if tab.get('type') == 'page':
            page_tab = tab
            break
    
    if not page_tab:
        print(json.dumps({"error": "No page tab found"}))
        sys.exit(1)
    
    # Get tab info
    tab_id = page_tab.get('id', '')
    ws_url = page_tab.get('webSocketDebuggerUrl', '')
    page_url = page_tab.get('url', '')
    
    result = {
        "tab_id": tab_id,
        "ws_url": ws_url,
        "page_url": page_url,
        "note": "CDP WebSocket connection required for full geolocation query"
    }
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
PYTHON_EOF

chmod +x "$VERIFY_DIR/query_geolocation.py"

# Execute the geolocation query script
echo "Querying geolocation via CDP..."
python3 "$VERIFY_DIR/query_geolocation.py" > "$VERIFY_DIR/geolocation_result.json" 2>/dev/null || echo '{"error": "Query failed"}' > "$VERIFY_DIR/geolocation_result.json"

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"