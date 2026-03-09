#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Responsive Design Mode Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture viewport state via CDP
echo "Capturing viewport dimensions via CDP..."

# Get active tab WebSocket URL
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_responsive.json 2>/dev/null; then
    echo "✓ CDP accessible, capturing tab information"
    
    # Extract active tab info
    ACTIVE_TAB=$(jq -r '.[0]' /tmp/chrome_tabs_responsive.json)
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // "unknown"')
    WS_URL=$(echo "$ACTIVE_TAB" | jq -r '.webSocketDebuggerUrl // ""')
    
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/responsive_active_url.txt
    echo "$WS_URL" > /tmp/responsive_ws_url.txt
    
    # Try to capture viewport dimensions using a simple Python script
    # This will be used by the verifier
    cat > /tmp/capture_viewport.py << 'PYEOF'
#!/usr/bin/env python3
import json
import sys

try:
    import websocket
    
    # Read WebSocket URL from file
    with open('/tmp/responsive_ws_url.txt', 'r') as f:
        ws_url = f.read().strip()
    
    if not ws_url:
        print("No WebSocket URL available", file=sys.stderr)
        sys.exit(1)
    
    # Connect and get viewport
    ws = websocket.create_connection(ws_url, timeout=5)
    
    # Execute JavaScript to get viewport dimensions
    cmd = {
        "id": 1,
        "method": "Runtime.evaluate",
        "params": {
            "expression": "JSON.stringify({ width: window.innerWidth, height: window.innerHeight, devicePixelRatio: window.devicePixelRatio, userAgent: navigator.userAgent })",
            "returnByValue": True
        }
    }
    ws.send(json.dumps(cmd))
    response = json.loads(ws.recv())
    
    if 'result' in response:
        result_value = response['result'].get('result', {}).get('value')
        if result_value:
            viewport_data = json.loads(result_value)
            
            # Save viewport data
            with open('/tmp/viewport_data.json', 'w') as f:
                json.dump(viewport_data, f, indent=2)
            
            print(f"Viewport: {viewport_data['width']}x{viewport_data['height']}")
            print(f"Device Pixel Ratio: {viewport_data['devicePixelRatio']}")
    
    ws.close()
    
except ImportError:
    print("websocket-client not available", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    
    chmod +x /tmp/capture_viewport.py
    python3 /tmp/capture_viewport.py 2>/dev/null || {
        echo "⚠ Could not capture viewport via WebSocket (may not be available)"
        # Create placeholder file
        echo '{"width": 0, "height": 0, "error": "capture_failed"}' > /tmp/viewport_data.json
    }
    
else
    echo "⚠ Warning: Chrome CDP not accessible"
    echo '{"error": "cdp_not_accessible"}' > /tmp/viewport_data.json
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/responsive_final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/responsive_final_screenshot.png"
fi

# Capture Chrome Preferences in case user agent override was set
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_prefs_responsive.json 2>/dev/null || true
    echo "Chrome Preferences exported for verification"
fi

echo "✅ Export complete"
echo "Viewport data saved to /tmp/viewport_data.json"