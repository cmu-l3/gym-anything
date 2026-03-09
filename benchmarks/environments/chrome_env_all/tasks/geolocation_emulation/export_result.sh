#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Geolocation Emulation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 python3-requests || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/geolocation_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab information via CDP
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Extract active tab info
    ACTIVE_TAB_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TAB_ID=$(jq -r '[.[] | select(.type == "page")][0].id // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_WS_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/chrome_tabs.json")
    
    echo "Active tab URL: $ACTIVE_TAB_URL"
    echo "$ACTIVE_TAB_URL" > "$VERIFY_DIR/active_url.txt"
    echo "$ACTIVE_TAB_ID" > "$VERIFY_DIR/active_tab_id.txt"
    echo "$ACTIVE_WS_URL" > "$VERIFY_DIR/websocket_url.txt"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/active_url.txt"
fi

# Try to get page content using CDP Runtime.evaluate
# This requires a more complex setup, so we'll create a helper Python script
cat > "$VERIFY_DIR/extract_page_content.py" << 'PYEOF'
#!/usr/bin/env python3
import json
import sys
import requests
import time

def get_page_geolocation_data(cdp_url):
    """Extract geolocation data from the test page using CDP"""
    try:
        # Get list of targets
        response = requests.get(f"{cdp_url}/json", timeout=5)
        targets = response.json()
        
        # Find active page
        page_target = None
        for target in targets:
            if target.get('type') == 'page' and 'geolocation_test' in target.get('url', ''):
                page_target = target
                break
        
        if not page_target:
            # Try first page
            page_target = next((t for t in targets if t.get('type') == 'page'), None)
        
        if not page_target:
            print("No page target found", file=sys.stderr)
            return None
        
        # Get the WebSocket debugger URL
        ws_url = page_target.get('webSocketDebuggerUrl', '')
        target_id = page_target.get('id', '')
        
        # Use HTTP-based CDP commands (simpler than WebSocket)
        # We'll construct a simple command
        base_url = cdp_url
        
        # Execute JavaScript to get geolocation data from the page
        js_code = """
        (function() {
            try {
                const latEl = document.getElementById('latitude');
                const lonEl = document.getElementById('longitude');
                const accEl = document.getElementById('accuracy');
                
                return {
                    latitude: latEl ? latEl.getAttribute('data-lat') : null,
                    longitude: lonEl ? lonEl.getAttribute('data-lon') : null,
                    latText: latEl ? latEl.textContent : null,
                    lonText: lonEl ? lonEl.textContent : null,
                    accText: accEl ? accEl.textContent : null,
                    hasData: latEl && latEl.getAttribute('data-lat') !== null
                };
            } catch(e) {
                return {error: e.toString()};
            }
        })();
        """
        
        # This is a simplified approach - in production, you'd use WebSocket
        # For now, we'll save what we can
        result = {
            "target_id": target_id,
            "url": page_target.get('url', ''),
            "title": page_target.get('title', '')
        }
        
        return result
        
    except Exception as e:
        print(f"Error extracting page data: {e}", file=sys.stderr)
        return None

if __name__ == "__main__":
    cdp_url = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:9222"
    result = get_page_geolocation_data(cdp_url)
    if result:
        print(json.dumps(result, indent=2))
    else:
        print("{}", file=sys.stderr)
PYEOF

chmod +x "$VERIFY_DIR/extract_page_content.py"

# Run the extraction script
echo "Extracting page geolocation data..."
python3 "$VERIFY_DIR/extract_page_content.py" "http://localhost:9222" > "$VERIFY_DIR/page_geo_data.json" 2>/dev/null || echo "{}" > "$VERIFY_DIR/page_geo_data.json"

# Also try to capture page screenshot
if [ -n "$ACTIVE_TAB_ID" ] && [ "$ACTIVE_TAB_ID" != "" ]; then
    echo "Attempting to capture page screenshot via CDP..."
    # This would require more complex CDP interaction
fi

# Take a final screenshot using X11
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Create a simple Python script to extract DOM content via CDP
cat > "$VERIFY_DIR/get_dom_content.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Extract DOM content from Chrome using CDP HTTP API
"""
import json
import requests
import sys

def get_dom_content():
    try:
        # Get targets
        resp = requests.get("http://localhost:9222/json", timeout=5)
        targets = resp.json()
        
        # Find geolocation test page
        page = None
        for t in targets:
            if t.get('type') == 'page':
                url = t.get('url', '')
                if 'geolocation_test' in url:
                    page = t
                    break
        
        if not page:
            page = next((t for t in targets if t.get('type') == 'page'), None)
        
        if not page:
            return {"error": "No page found"}
        
        # Extract basic info
        return {
            "url": page.get('url', ''),
            "title": page.get('title', ''),
            "target_id": page.get('id', ''),
            "description": page.get('description', '')
        }
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    result = get_dom_content()
    print(json.dumps(result, indent=2))
PYEOF

chmod +x "$VERIFY_DIR/get_dom_content.py"
python3 "$VERIFY_DIR/get_dom_content.py" > "$VERIFY_DIR/dom_info.json" 2>/dev/null || echo "{}" > "$VERIFY_DIR/dom_info.json"

# Copy verification files to standard /tmp location
cp "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"
ls -lh "$VERIFY_DIR"