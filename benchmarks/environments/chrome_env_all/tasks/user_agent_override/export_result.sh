#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome User Agent Override Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 python3-pip || true
pip3 install -q websocket-client 2>/dev/null || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/ua_override_verification"
mkdir -p "$VERIFY_DIR"

# Capture CDP tab information
echo "Capturing CDP tab information..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Extract active tab info
    jq '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_tabs.json" > "$VERIFY_DIR/active_tab.json" 2>/dev/null || true
    
    ACTIVE_URL=$(jq -r '.url // ""' "$VERIFY_DIR/active_tab.json" 2>/dev/null)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
else
    echo "⚠ Warning: Could not capture CDP information"
    echo "{}" > "$VERIFY_DIR/chrome_tabs.json"
    echo "" > "$VERIFY_DIR/final_url.txt"
fi

# Create Python script to execute JavaScript via CDP and get user agent
echo "Creating CDP JavaScript executor..."
cat > "$VERIFY_DIR/get_user_agent.py" << 'PYEOF'
#!/usr/bin/env python3
import json
import sys

try:
    import websocket
    import requests
    
    # Get WebSocket URL from CDP
    response = requests.get('http://localhost:9222/json', timeout=5)
    tabs = response.json()
    
    if not tabs:
        print("ERROR: No tabs found", file=sys.stderr)
        sys.exit(1)
    
    # Get first page tab
    page_tab = None
    for tab in tabs:
        if tab.get('type') == 'page':
            page_tab = tab
            break
    
    if not page_tab:
        print("ERROR: No page tab found", file=sys.stderr)
        sys.exit(1)
    
    ws_url = page_tab.get('webSocketDebuggerUrl')
    if not ws_url:
        print("ERROR: No WebSocket URL", file=sys.stderr)
        sys.exit(1)
    
    # Connect to WebSocket and execute JavaScript
    ws = websocket.create_connection(ws_url, timeout=5)
    
    # Execute navigator.userAgent
    command = {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": "navigator.userAgent",
            "returnByValue": True
        }
    }
    
    ws.send(json.dumps(command))
    result = json.loads(ws.recv())
    ws.close()
    
    if 'result' in result and 'result' in result['result']:
        user_agent = result['result']['result'].get('value', '')
        print(user_agent)
        sys.exit(0)
    else:
        print("ERROR: Could not extract user agent from result", file=sys.stderr)
        print(json.dumps(result), file=sys.stderr)
        sys.exit(1)

except ImportError as e:
    print(f"ERROR: Required library not available: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF

chmod +x "$VERIFY_DIR/get_user_agent.py"

# Execute the Python script to get user agent
echo "Attempting to extract user agent via CDP JavaScript execution..."
if python3 "$VERIFY_DIR/get_user_agent.py" > "$VERIFY_DIR/user_agent.txt" 2> "$VERIFY_DIR/ua_error.log"; then
    CAPTURED_UA=$(cat "$VERIFY_DIR/user_agent.txt")
    echo "✓ User agent captured: ${CAPTURED_UA:0:80}..."
else
    echo "⚠ Could not execute JavaScript via CDP, checking error log..."
    if [ -f "$VERIFY_DIR/ua_error.log" ]; then
        cat "$VERIFY_DIR/ua_error.log"
    fi
    echo "unknown" > "$VERIFY_DIR/user_agent.txt"
fi

# Export Chrome Preferences for fallback verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
        echo "✓ Preferences exported from: $CHROME_PROFILE"
        break
    fi
done

if [ ! -f "$VERIFY_DIR/chrome_preferences.json" ]; then
    echo "⚠ Warning: Could not find Chrome Preferences file"
    echo "{}" > "$VERIFY_DIR/chrome_preferences.json"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"