#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Picture-in-Picture Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq xdotool wmctrl || true

# Create verification directory
VERIFY_DIR="/tmp/pip_verification"
mkdir -p "$VERIFY_DIR"

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture window list to check for PiP window
echo "Capturing window information..."
export DISPLAY=:1
wmctrl -l > "$VERIFY_DIR/window_list.txt" 2>/dev/null || echo "wmctrl failed" > "$VERIFY_DIR/window_list.txt"
echo "Window list captured"

# Search for PiP-specific window patterns
echo "Searching for PiP window patterns..."
wmctrl -l | grep -i "picture\|pip\|video" > "$VERIFY_DIR/pip_window_matches.txt" 2>/dev/null || echo "no matches" > "$VERIFY_DIR/pip_window_matches.txt"

# Get all Chrome window IDs and their properties
echo "Capturing Chrome window properties..."
xdotool search --class chrome > "$VERIFY_DIR/chrome_window_ids.txt" 2>/dev/null || echo "" > "$VERIFY_DIR/chrome_window_ids.txt"

# For each Chrome window, capture its geometry (small windows might be PiP)
while read -r window_id; do
    if [ -n "$window_id" ]; then
        xwininfo -id "$window_id" 2>/dev/null | grep -E "Width:|Height:|Absolute" >> "$VERIFY_DIR/window_geometry.txt" || true
        echo "---" >> "$VERIFY_DIR/window_geometry.txt"
    fi
done < "$VERIFY_DIR/chrome_window_ids.txt"

# Capture active tab information via CDP
echo "Capturing CDP tab information..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tabs information captured"
    
    # Extract active tab URL and title
    ACTIVE_TAB=$(jq -r '[.[] | select(.type == "page")][0]' "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null || echo "{}")
    echo "$ACTIVE_TAB" > "$VERIFY_DIR/active_tab.json"
    
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    echo "$ACTIVE_URL" > "$VERIFY_DIR/active_url.txt"
    echo "Active URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Could not capture CDP information"
    echo "{}" > "$VERIFY_DIR/chrome_tabs.json"
    echo "" > "$VERIFY_DIR/active_url.txt"
fi

# Execute JavaScript via CDP to check PiP state
# This is more reliable than just checking windows
echo "Checking PiP state via JavaScript execution..."
if command -v python3 &> /dev/null; then
    python3 - << 'PYTHON_SCRIPT' > "$VERIFY_DIR/pip_state.json" 2>/dev/null || echo '{"pip_active": false, "error": "script failed"}' > "$VERIFY_DIR/pip_state.json"
import json
import urllib.request
import urllib.error

try:
    # Get list of tabs
    response = urllib.request.urlopen('http://localhost:9222/json', timeout=5)
    tabs = json.loads(response.read().decode())
    
    # Find the video test page
    video_tab = None
    for tab in tabs:
        if tab.get('type') == 'page' and 'pip_test_video.html' in tab.get('url', ''):
            video_tab = tab
            break
    
    if video_tab:
        # In a full implementation, we would connect via WebSocket to execute JS
        # For now, we record that we found the tab
        result = {
            "pip_active": False,
            "video_tab_found": True,
            "video_tab_url": video_tab.get('url', ''),
            "note": "Full JS execution requires WebSocket connection"
        }
    else:
        result = {
            "pip_active": False,
            "video_tab_found": False,
            "note": "Video test page not found in tabs"
        }
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"pip_active": False, "error": str(e)}))
PYTHON_SCRIPT
else
    echo '{"pip_active": false, "error": "python3 not available"}' > "$VERIFY_DIR/pip_state.json"
fi

# Take screenshots for visual verification
echo "Capturing screenshots..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/full_screen.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Check running Chrome processes (PiP might create additional processes)
echo "Capturing Chrome process information..."
ps aux | grep -i chrome > "$VERIFY_DIR/chrome_processes.txt" 2>/dev/null || echo "ps failed" > "$VERIFY_DIR/chrome_processes.txt"

# Count Chrome windows (PiP creates an additional window)
CHROME_WINDOW_COUNT=$(wmctrl -l | grep -i chrome | wc -l)
echo "$CHROME_WINDOW_COUNT" > "$VERIFY_DIR/chrome_window_count.txt"
echo "Chrome window count: $CHROME_WINDOW_COUNT"

# Export all verification data summary
cat > "$VERIFY_DIR/summary.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "chrome_window_count": $CHROME_WINDOW_COUNT,
  "verification_files": [
    "window_list.txt",
    "pip_window_matches.txt",
    "chrome_tabs.json",
    "active_tab.json",
    "pip_state.json",
    "full_screen.png",
    "window_geometry.txt"
  ]
}
EOF

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"
ls -la "$VERIFY_DIR"