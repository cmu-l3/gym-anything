#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Network Throttling Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/network_throttling_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing Chrome state via CDP..."

# Check if DevTools is open by looking for devtools:// tabs
if curl -s http://localhost:9222/json > "$VERIFY_DIR/final_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Count devtools tabs (indicates DevTools is open)
    DEVTOOLS_COUNT=$(jq '[.[] | select(.url | contains("devtools://"))] | length' "$VERIFY_DIR/final_tabs.json" 2>/dev/null || echo "0")
    echo "✓ DevTools tabs detected: $DEVTOOLS_COUNT"
    echo "$DEVTOOLS_COUNT" > "$VERIFY_DIR/devtools_open_count.txt"
    
    # Get active page tab (not devtools)
    jq '[.[] | select(.type == "page" and (.url | contains("devtools://") | not))] | .[0]' "$VERIFY_DIR/final_tabs.json" > "$VERIFY_DIR/active_page_tab.json" 2>/dev/null || echo "{}" > "$VERIFY_DIR/active_page_tab.json"
    
    ACTIVE_URL=$(jq -r '.url // "unknown"' "$VERIFY_DIR/active_page_tab.json")
    echo "✓ Active page URL: $ACTIVE_URL"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "0" > "$VERIFY_DIR/devtools_open_count.txt"
    echo "{}" > "$VERIFY_DIR/active_page_tab.json"
fi

# Reload the test page to capture network timing under current throttling state
echo "Reloading test page to capture network timing..."

# Give a moment for any throttling settings to be stable
sleep 1

# Get the webSocketDebuggerUrl for the active page tab
WS_URL=$(jq -r '.webSocketDebuggerUrl // ""' "$VERIFY_DIR/active_page_tab.json")

if [ -n "$WS_URL" ] && [ "$WS_URL" != "" ] && [ "$WS_URL" != "null" ]; then
    echo "WebSocket URL for active tab: $WS_URL"
    echo "$WS_URL" > "$VERIFY_DIR/ws_url.txt"
    
    # Reload page via browser automation (more reliable than CDP for this)
    su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
    sleep 0.5
    su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers F5" || true
    sleep 1
    
    # Wait for page to start loading
    sleep 3
    
    # Capture timing after reload
    date +%s%3N > "$VERIFY_DIR/reload_timestamp.txt"
    
    # Get updated tab info with timing
    curl -s http://localhost:9222/json > "$VERIFY_DIR/post_reload_tabs.json" 2>/dev/null || echo "[]" > "$VERIFY_DIR/post_reload_tabs.json"
else
    echo "⚠ Could not get WebSocket URL for timing capture"
    echo "" > "$VERIFY_DIR/ws_url.txt"
    echo "0" > "$VERIFY_DIR/reload_timestamp.txt"
fi

# Take a screenshot showing DevTools state
echo "Capturing screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    
    if [ -f "$VERIFY_DIR/final_screenshot.png" ]; then
        FILE_SIZE=$(stat -f%z "$VERIFY_DIR/final_screenshot.png" 2>/dev/null || stat -c%s "$VERIFY_DIR/final_screenshot.png" 2>/dev/null || echo "0")
        echo "✓ Screenshot captured (${FILE_SIZE} bytes)"
    fi
fi

# Try to detect visual signs of throttling in screenshot (optional enhancement)
# We'll look for the Network panel being visible
if [ -f "$VERIFY_DIR/final_screenshot.png" ] && command -v convert &> /dev/null; then
    # Create a small cropped version of the Network panel area (approximate location)
    # This is just for additional evidence, not primary verification
    convert "$VERIFY_DIR/final_screenshot.png" -crop 600x100+100+100 "$VERIFY_DIR/network_panel_area.png" 2>/dev/null || true
fi

# Export Chrome Preferences as supplementary evidence (though throttling is not stored there)
echo "Exporting Chrome Preferences for supplementary checks..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json" 2>/dev/null || true
else
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json" 2>/dev/null || true
    fi
fi

# Create summary file
cat > "$VERIFY_DIR/summary.txt" << EOF
=== Network Throttling Task Export Summary ===
Timestamp: $(date)
DevTools Open Count: $(cat "$VERIFY_DIR/devtools_open_count.txt" 2>/dev/null || echo "unknown")
Active URL: $ACTIVE_URL

Files exported:
$(ls -lh "$VERIFY_DIR" 2>/dev/null | tail -n +2)
EOF

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"
cat "$VERIFY_DIR/summary.txt"