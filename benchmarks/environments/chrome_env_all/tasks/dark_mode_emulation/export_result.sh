#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Dark Mode Emulation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/dark_mode_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing Chrome state via CDP..."

# Get active tab information
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tabs information captured"
    
    # Extract active page tab
    jq '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_tabs.json" > "$VERIFY_DIR/active_tab.json" || true
    
    # Get WebSocket URL for the active tab
    WS_URL=$(jq -r '.webSocketDebuggerUrl // ""' "$VERIFY_DIR/active_tab.json")
    
    if [ -n "$WS_URL" ] && [ "$WS_URL" != "null" ]; then
        echo "✓ Active tab WebSocket URL: $WS_URL"
        echo "$WS_URL" > "$VERIFY_DIR/ws_url.txt"
    fi
else
    echo "⚠ Warning: Could not capture CDP information"
    echo "{}" > "$VERIFY_DIR/chrome_tabs.json"
    echo "{}" > "$VERIFY_DIR/active_tab.json"
fi

# Execute JavaScript via CDP to capture computed styles
echo "Executing JavaScript to capture page state..."

# Create a Python script to interact with CDP via HTTP
cat > /tmp/capture_dark_mode_state.py << 'PYEOF'
#!/usr/bin/env python3
import json
import sys

try:
    import requests
except ImportError:
    print("requests module not available", file=sys.stderr)
    sys.exit(1)

def capture_page_state():
    """Capture page state via CDP"""
    try:
        # Get all tabs
        response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = response.json()
        
        # Find the page tab (not DevTools)
        page_tab = None
        for tab in tabs:
            if tab.get('type') == 'page' and 'devtools' not in tab.get('url', '').lower():
                if 'dark_mode_test.html' in tab.get('url', ''):
                    page_tab = tab
                    break
        
        if not page_tab:
            # Fallback to first page tab
            for tab in tabs:
                if tab.get('type') == 'page' and 'devtools' not in tab.get('url', '').lower():
                    page_tab = tab
                    break
        
        if not page_tab:
            return {"error": "No page tab found"}
        
        # Get WebSocket debugger URL
        ws_url = page_tab.get('webSocketDebuggerUrl', '')
        if not ws_url:
            return {"error": "No WebSocket URL available"}
        
        # Use HTTP endpoint instead of WebSocket for simplicity
        # Get the tab ID
        tab_id = page_tab.get('id', '')
        
        # Execute JavaScript to get computed styles
        # We'll use the /json endpoint which sometimes allows execution
        # For more robust solution, would need websocket library
        
        # Alternative: Try to parse URL and title for clues
        result = {
            "url": page_tab.get('url', ''),
            "title": page_tab.get('title', ''),
            "tab_id": tab_id,
            "ws_url": ws_url
        }
        
        return result
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == '__main__':
    result = capture_page_state()
    print(json.dumps(result, indent=2))
PYEOF

chmod +x /tmp/capture_dark_mode_state.py
python3 /tmp/capture_dark_mode_state.py > "$VERIFY_DIR/page_state.json" 2>/dev/null || echo '{"error": "Failed to capture"}' > "$VERIFY_DIR/page_state.json"

# Alternative: Use CDP HTTP API to execute JavaScript
# Get the first page target
TARGET_ID=$(jq -r '[.[] | select(.type == "page")][0].id // ""' "$VERIFY_DIR/chrome_tabs.json")

if [ -n "$TARGET_ID" ] && [ "$TARGET_ID" != "null" ]; then
    echo "Attempting to execute JavaScript via CDP..."
    
    # Try to get computed background color
    cat > /tmp/cdp_eval.json << EOF
{
  "id": 1,
  "method": "Runtime.evaluate",
  "params": {
    "expression": "(function() { try { const body = document.body; const bg = getComputedStyle(body).backgroundColor; const rgb = bg.match(/\\\\d+/g); if (!rgb) return {error: 'Could not parse color'}; const r = parseInt(rgb[0]); const g = parseInt(rgb[1]); const b = parseInt(rgb[2]); const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255; return { backgroundColor: bg, rgb: {r, g, b}, luminance: luminance, isDark: luminance < 0.3, isDarkModeActive: window.matchMedia('(prefers-color-scheme: dark)').matches }; } catch(e) { return {error: e.toString()}; } })()",
    "returnByValue": true
  }
}
EOF
    
    # Note: Full CDP command requires WebSocket connection
    # For now, save the command for potential use
    cp /tmp/cdp_eval.json "$VERIFY_DIR/cdp_command.json"
fi

# Take screenshots for visual verification
echo "Taking screenshots..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved"
fi

# Capture final URL
FINAL_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
echo "$FINAL_URL" > "$VERIFY_DIR/final_url.txt"
echo "Final URL: $FINAL_URL"

# Copy all verification data to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files in: $VERIFY_DIR"