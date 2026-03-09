#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome localStorage DevTools Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 python3-requests || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create a Python script to extract localStorage via CDP
cat > /tmp/extract_localstorage.py << 'PYEOF'
#!/usr/bin/env python3
"""
Extract localStorage from active Chrome tab using Chrome DevTools Protocol
"""
import json
import sys
import requests
import time

def get_active_tab():
    """Get the active tab from Chrome CDP"""
    try:
        response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = response.json()
        
        # Find tabs with localhost:8765 (our test page)
        target_tabs = [t for t in tabs if t.get('type') == 'page' and 'localhost:8765' in t.get('url', '')]
        
        if target_tabs:
            return target_tabs[0]
        
        # Fallback to first page tab
        page_tabs = [t for t in tabs if t.get('type') == 'page']
        if page_tabs:
            return page_tabs[0]
        
        return None
    except Exception as e:
        print(f"Error getting tabs: {e}", file=sys.stderr)
        return None

def extract_localstorage_via_http(tab):
    """
    Extract localStorage using CDP HTTP API
    Note: This is a simplified approach. Full CDP requires WebSocket.
    We'll inject JavaScript and read the result.
    """
    try:
        # For simplicity, we'll use a workaround:
        # Execute JavaScript via the Runtime domain (requires WebSocket or advanced CDP client)
        # Since we don't have websocket-client in base environment, we use an alternative:
        
        # Alternative: Use Chrome's built-in JavaScript execution via --remote-debugging-port
        # However, this requires WebSocket connection which is complex.
        
        # Simple fallback: Return empty dict and let verifier use alternative method
        return {}
        
    except Exception as e:
        print(f"Error extracting localStorage: {e}", file=sys.stderr)
        return {}

def extract_localstorage_from_dom():
    """
    Alternative method: Read localStorage by checking what's displayed on the page
    The test page displays localStorage contents in real-time.
    However, this is not reliable for programmatic verification.
    """
    # This is a placeholder - in reality we'd need proper CDP WebSocket client
    return {}

def main():
    print("Attempting to extract localStorage via CDP...", file=sys.stderr)
    
    tab = get_active_tab()
    if not tab:
        print("Could not find active tab", file=sys.stderr)
        # Create empty localStorage data
        result = {
            "origin": "http://localhost:8765",
            "entries": {},
            "extraction_method": "failed"
        }
    else:
        print(f"Found tab: {tab.get('url', 'unknown')}", file=sys.stderr)
        
        # Since we don't have full CDP WebSocket support, we'll need to use
        # an alternative method or install additional packages
        # For now, create a placeholder structure
        result = {
            "origin": tab.get('url', ''),
            "entries": {},
            "extraction_method": "placeholder",
            "tab_id": tab.get('id', '')
        }
    
    # Save result
    with open('/tmp/localstorage_data.json', 'w') as f:
        json.dump(result, f, indent=2)
    
    print("localStorage data saved to /tmp/localstorage_data.json", file=sys.stderr)

if __name__ == '__main__':
    main()
PYEOF

chmod +x /tmp/extract_localstorage.py

# Try to extract localStorage using Python CDP client
echo "Extracting localStorage via CDP..."
python3 /tmp/extract_localstorage.py 2>&1 | tee /tmp/extract_localstorage.log

# Alternative method: Use Chrome's console to export localStorage
# This is more reliable than complex CDP WebSocket handling
echo "Using alternative method: JavaScript injection via CDP..."

# Get active tab information
curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null || true

# Extract tab info
ACTIVE_TAB_URL=$(jq -r '[.[] | select(.type == "page" and (.url | contains("localhost:8765")))][0].url // ""' /tmp/chrome_tabs.json 2>/dev/null || echo "")
ACTIVE_TAB_ID=$(jq -r '[.[] | select(.type == "page" and (.url | contains("localhost:8765")))][0].id // ""' /tmp/chrome_tabs.json 2>/dev/null || echo "")

echo "Active tab URL: $ACTIVE_TAB_URL"
echo "Active tab ID: $ACTIVE_TAB_ID"

# Create a more sophisticated extraction script with CDP WebSocket support
# Install websocket-client if needed
pip3 install -q websocket-client 2>/dev/null || true

cat > /tmp/extract_localstorage_ws.py << 'PYEOF2'
#!/usr/bin/env python3
"""
Extract localStorage using WebSocket-based CDP client
"""
import json
import sys
import requests

try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False
    print("websocket-client not available, using fallback", file=sys.stderr)

def extract_with_websocket():
    """Extract localStorage using WebSocket CDP connection"""
    if not HAS_WEBSOCKET:
        return None
    
    try:
        # Get target tab
        response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = response.json()
        
        target_tab = None
        for tab in tabs:
            if tab.get('type') == 'page' and 'localhost:8765' in tab.get('url', ''):
                target_tab = tab
                break
        
        if not target_tab:
            print("Target tab not found", file=sys.stderr)
            return None
        
        ws_url = target_tab.get('webSocketDebuggerUrl')
        if not ws_url:
            print("WebSocket URL not available", file=sys.stderr)
            return None
        
        # Connect via WebSocket
        ws = websocket.create_connection(ws_url, timeout=5)
        
        # Execute JavaScript to get localStorage
        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": "JSON.stringify(Object.assign({}, localStorage))",
                "returnByValue": True
            }
        }
        
        ws.send(json.dumps(command))
        result = json.loads(ws.recv())
        ws.close()
        
        if 'result' in result and 'result' in result['result']:
            storage_json = result['result']['result'].get('value', '{}')
            storage_data = json.loads(storage_json)
            return storage_data
        
        return None
        
    except Exception as e:
        print(f"WebSocket extraction failed: {e}", file=sys.stderr)
        return None

def main():
    storage_data = extract_with_websocket()
    
    if storage_data is None:
        # Fallback: create empty structure
        storage_data = {}
    
    result = {
        "origin": "http://localhost:8765",
        "entries": storage_data,
        "extraction_method": "websocket" if storage_data else "failed",
        "timestamp": str(int(time.time()) if 'time' in dir() else 0)
    }
    
    with open('/tmp/localstorage_data.json', 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Extracted {len(storage_data)} localStorage entries", file=sys.stderr)
    print(f"Entries: {list(storage_data.keys())}", file=sys.stderr)

if __name__ == '__main__':
    import time
    main()
PYEOF2

chmod +x /tmp/extract_localstorage_ws.py
python3 /tmp/extract_localstorage_ws.py 2>&1 | tee -a /tmp/extract_localstorage.log

# Verify extraction results
if [ -f /tmp/localstorage_data.json ]; then
    echo "✓ localStorage data file created"
    cat /tmp/localstorage_data.json
else
    echo "⚠ localStorage data file not created, creating empty structure"
    echo '{"origin":"http://localhost:8765","entries":{},"extraction_method":"failed"}' > /tmp/localstorage_data.json
fi

# Capture active tab URL for additional context
echo "$ACTIVE_TAB_URL" > /tmp/final_url.txt

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Stop the HTTP server
if [ -f /tmp/http_server.pid ]; then
    HTTP_PID=$(cat /tmp/http_server.pid)
    kill $HTTP_PID 2>/dev/null || true
    echo "HTTP server stopped"
fi

echo "✅ Export complete"
echo "localStorage data available at: /tmp/localstorage_data.json"