#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools DOM Modification Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick python3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/devtools_verification"
mkdir -p "$VERIFY_DIR"

# Capture screenshot of the current state
echo "Capturing screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    
    if [ -f "$VERIFY_DIR/final_screenshot.png" ]; then
        echo "✓ Screenshot saved: $VERIFY_DIR/final_screenshot.png"
        ls -lh "$VERIFY_DIR/final_screenshot.png"
    else
        echo "⚠ Warning: Screenshot file not created"
    fi
else
    echo "⚠ Warning: import command (ImageMagick) not available"
fi

# Try to capture button computed style via CDP
echo "Attempting to capture button style via CDP..."

# Get active tab's WebSocket debugger URL
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Extract active tab URL and title
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    WS_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/chrome_tabs.json")
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/active_title.txt"
    echo "$WS_URL" > "$VERIFY_DIR/websocket_url.txt"
    
    # Try to get button color using a simple Python script via CDP
    # Note: This requires websocket which might not be available
    # So we'll create a best-effort script
    
    cat > "$VERIFY_DIR/get_button_color.py" << 'PYTHON_SCRIPT'
#!/usr/bin/env python3
import json
import sys

try:
    # Try to use websocket if available
    import websocket
    import json
    
    # Read WebSocket URL
    with open('/tmp/devtools_verification/websocket_url.txt', 'r') as f:
        ws_url = f.read().strip()
    
    if ws_url:
        ws = websocket.create_connection(ws_url, timeout=5)
        
        # Send Runtime.evaluate command to get button background color
        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": """
                    (function() {
                        const button = document.querySelector('button');
                        if (!button) return 'button-not-found';
                        const style = window.getComputedStyle(button);
                        return style.backgroundColor;
                    })()
                """
            }
        }
        
        ws.send(json.dumps(command))
        response = ws.recv()
        ws.close()
        
        result = json.loads(response)
        if 'result' in result and 'result' in result['result']:
            color_value = result['result']['result']['value']
            print(color_value)
            with open('/tmp/devtools_verification/button_computed_color.txt', 'w') as f:
                f.write(color_value)
            sys.exit(0)
except ImportError:
    # websocket library not available
    pass
except Exception as e:
    # Any error in CDP communication
    pass

# Fallback: indicate CDP script couldn't run
with open('/tmp/devtools_verification/button_computed_color.txt', 'w') as f:
    f.write('cdp-unavailable')
PYTHON_SCRIPT

    chmod +x "$VERIFY_DIR/get_button_color.py"
    python3 "$VERIFY_DIR/get_button_color.py" 2>/dev/null || echo "cdp-script-failed" > "$VERIFY_DIR/button_computed_color.txt"
    
    if [ -f "$VERIFY_DIR/button_computed_color.txt" ]; then
        BUTTON_COLOR=$(cat "$VERIFY_DIR/button_computed_color.txt")
        echo "Button computed color: $BUTTON_COLOR"
    fi
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "cdp-failed" > "$VERIFY_DIR/button_computed_color.txt"
fi

# Copy original button color reference
if [ -f "/tmp/original_button_color.txt" ]; then
    cp "/tmp/original_button_color.txt" "$VERIFY_DIR/original_button_color.txt"
fi

# Copy all verification files to standard /tmp location for easy access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files in: $VERIFY_DIR"
ls -la "$VERIFY_DIR"