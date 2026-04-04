#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome LocalStorage Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 python3-requests || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create Python script to extract localStorage via CDP
cat > /tmp/extract_localstorage.py << 'PYEOF'
#!/usr/bin/env python3
import json
import sys
import requests

def extract_localstorage_via_cdp():
    """Extract localStorage using Chrome DevTools Protocol"""
    try:
        # Get all tabs
        response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = response.json()
        
        # Find the test page tab (localhost:8000)
        target_tab = None
        for tab in tabs:
            if tab.get('type') == 'page':
                url = tab.get('url', '')
                if 'localhost:8000' in url or '127.0.0.1:8000' in url:
                    target_tab = tab
                    break
        
        if not target_tab:
            # Use first page tab as fallback
            for tab in tabs:
                if tab.get('type') == 'page':
                    target_tab = tab
                    break
        
        if not target_tab:
            print(json.dumps({"error": "No active page tab found"}))
            return
        
        tab_id = target_tab.get('id')
        ws_url = target_tab.get('webSocketDebuggerUrl')
        
        if not ws_url:
            print(json.dumps({"error": "No WebSocket URL available"}))
            return
        
        # Try websocket connection if available
        try:
            import websocket
            ws = websocket.create_connection(ws_url, timeout=5)
            
            # Execute JavaScript to get localStorage
            command = {
                "id": 1,
                "method": "Runtime.evaluate",
                "params": {
                    "expression": """
                    (() => {
                        const storage = {};
                        for (let i = 0; i < localStorage.length; i++) {
                            const key = localStorage.key(i);
                            storage[key] = localStorage.getItem(key);
                        }
                        return JSON.stringify(storage);
                    })()
                    """,
                    "returnByValue": True
                }
            }
            
            ws.send(json.dumps(command))
            result = json.loads(ws.recv())
            ws.close()
            
            if 'result' in result and 'result' in result['result']:
                storage_json = result['result']['result']['value']
                storage_data = json.loads(storage_json)
                print(json.dumps({
                    "success": True,
                    "localStorage": storage_data,
                    "url": target_tab.get('url')
                }))
                return
        except ImportError:
            pass  # websocket-client not available, try HTTP fallback
        except Exception as e:
            print(json.dumps({"error": f"WebSocket error: {str(e)}"}), file=sys.stderr)
        
        # Fallback: Use HTTP-based CDP (limited functionality)
        # This won't work for Runtime.evaluate without WebSocket
        print(json.dumps({
            "error": "WebSocket connection required but not available",
            "tab_url": target_tab.get('url'),
            "tab_title": target_tab.get('title')
        }))
        
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    extract_localstorage_via_cdp()
PYEOF

chmod +x /tmp/extract_localstorage.py

# Execute the extraction script
echo "Extracting localStorage via CDP..."
python3 /tmp/extract_localstorage.py > /tmp/localstorage_data.json 2>/tmp/localstorage_extract_error.log

# Check if extraction was successful
if [ -f /tmp/localstorage_data.json ]; then
    echo "✓ LocalStorage data extracted"
    cat /tmp/localstorage_data.json | head -c 500
    echo ""
else
    echo "⚠ Warning: LocalStorage extraction may have failed"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab information..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Stop the HTTP server
if [ -f /tmp/localstorage_server.pid ]; then
    SERVER_PID=$(cat /tmp/localstorage_server.pid)
    kill $SERVER_PID 2>/dev/null || true
    rm /tmp/localstorage_server.pid
    echo "HTTP server stopped"
fi

echo "✅ Export complete"