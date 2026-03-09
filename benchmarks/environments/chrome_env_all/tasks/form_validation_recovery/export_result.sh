#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Form Validation Recovery Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/form_validation_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab information via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    
    # Copy full tab data for detailed verification
    cp /tmp/chrome_tabs.json "$VERIFY_DIR/"
fi

# Use CDP to check DOM for error elements and success indicators
echo "Querying page DOM via CDP..."
if command -v python3 &> /dev/null; then
    python3 << 'PYTHON_SCRIPT' > "$VERIFY_DIR/dom_state.json" 2>/dev/null || true
import json
import urllib.request
import urllib.error

try:
    # Get first page tab
    response = urllib.request.urlopen('http://localhost:9222/json', timeout=5)
    tabs = json.loads(response.read().decode())
    page_tabs = [t for t in tabs if t.get('type') == 'page']
    
    if not page_tabs:
        print(json.dumps({'error': 'No page tabs found'}))
        exit()
    
    ws_url = page_tabs[0].get('webSocketDebuggerUrl', '')
    
    # For simplicity, we'll check URL and title which we already have
    # Full CDP WebSocket inspection would be more complex
    dom_state = {
        'url': page_tabs[0].get('url', ''),
        'title': page_tabs[0].get('title', ''),
        'has_success_indicators': 'success' in page_tabs[0].get('url', '').lower() or 'success' in page_tabs[0].get('title', '').lower()
    }
    
    print(json.dumps(dom_state))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
PYTHON_SCRIPT
fi

# Check if on success page
if echo "$ACTIVE_URL" | grep -q "success.html"; then
    echo "✓ Agent reached success page"
    echo "success" > "$VERIFY_DIR/submission_status.txt"
elif echo "$ACTIVE_TITLE" | grep -iq "success"; then
    echo "✓ Agent on success page (detected via title)"
    echo "success" > "$VERIFY_DIR/submission_status.txt"
else
    echo "⚠ Agent not on success page"
    echo "incomplete" > "$VERIFY_DIR/submission_status.txt"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Stop HTTP server
echo "Stopping HTTP server..."
pkill -f "python3.*http.server.*8765" || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"