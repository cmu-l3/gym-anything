#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools LocalStorage Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 2>/dev/null || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture localStorage via CDP JavaScript injection
echo "Capturing localStorage state via CDP..."

# Get the active tab's webSocketDebuggerUrl
CDP_INFO=$(curl -s http://localhost:9222/json 2>/dev/null)
WS_URL=$(echo "$CDP_INFO" | jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""')

if [ -z "$WS_URL" ]; then
    echo "⚠ Warning: Could not get WebSocket debugger URL"
    echo "{}" > /tmp/localstorage_state.json
else
    echo "✓ Found WebSocket URL: ${WS_URL:0:50}..."
    
    # Create Python script to query localStorage via CDP
    cat > /tmp/query_localstorage.py << 'PYEOF'
#!/usr/bin/env python3
import json
import sys

try:
    import requests
except ImportError:
    print("requests module not available, installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "requests"])
    import requests

def get_localstorage_via_cdp():
    """Query localStorage using Chrome DevTools Protocol"""
    try:
        # Get tab information
        tabs_response = requests.get('http://localhost:9222/json', timeout=5)
        tabs = tabs_response.json()
        
        # Find the page tab (not background pages or extensions)
        page_tab = None
        for tab in tabs:
            if tab.get('type') == 'page':
                page_tab = tab
                break
        
        if not page_tab:
            return {"error": "No page tab found"}
        
        tab_id = page_tab.get('id')
        
        # Use CDP Runtime.evaluate to execute JavaScript that reads localStorage
        cdp_url = f"http://localhost:9222/json/new"
        
        # JavaScript to read all localStorage items
        js_code = """
        (function() {
            const result = {};
            try {
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    if (key !== '_initialized') {
                        result[key] = localStorage.getItem(key);
                    }
                }
                return result;
            } catch (e) {
                return {error: e.toString()};
            }
        })()
        """
        
        # For simplicity, we'll use a different approach: inject via URL
        # Actually, let's use the simpler CDP HTTP API
        
        # Get current page URL to verify it's our test page
        page_url = page_tab.get('url', '')
        
        # Since we can't easily use WebSocket from bash, we'll store the info
        # and let the Python verifier handle CDP communication
        return {
            "method": "cdp_available",
            "page_url": page_url,
            "tab_id": tab_id
        }
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    result = get_localstorage_via_cdp()
    print(json.dumps(result, indent=2))
PYEOF
    
    chmod +x /tmp/query_localstorage.py
    python3 /tmp/query_localstorage.py > /tmp/cdp_info.json 2>/dev/null || echo '{"error": "CDP query failed"}' > /tmp/cdp_info.json
    
    echo "✓ CDP information captured"
fi

# Also capture active tab URL
echo "Capturing active tab URL..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Don't close Chrome - verifier needs it running for CDP queries
echo "✓ Keeping Chrome running for CDP verification"

echo "✅ Export complete"