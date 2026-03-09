#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Zoom Accessibility Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/zoom_verification"
mkdir -p "$VERIFY_DIR"

# Capture final zoom level via CDP (if possible)
echo "Attempting to capture zoom level via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_zoom.json 2>/dev/null; then
    # Get active tab info
    ACTIVE_TAB=$(jq -r '[.[] | select(.type == "page")][0]' /tmp/chrome_tabs_zoom.json)
    ACTIVE_URL=$(echo "$ACTIVE_TAB" | jq -r '.url // ""')
    ACTIVE_TITLE=$(echo "$ACTIVE_TAB" | jq -r '.title // ""')
    
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    
    # Try to get zoom level via CDP (requires webSocketDebuggerUrl)
    WS_URL=$(echo "$ACTIVE_TAB" | jq -r '.webSocketDebuggerUrl // ""')
    if [ -n "$WS_URL" ]; then
        echo "CDP WebSocket available: $WS_URL"
        echo "$WS_URL" > "$VERIFY_DIR/cdp_websocket.txt"
    fi
fi

# Take a final screenshot to show zoom state
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save zoom preferences..."

# Send SIGTERM for graceful shutdown
pkill -SIGTERM -f "google-chrome" || true
sleep 2

# Wait for Chrome to fully close and save preferences
for i in {1..5}; do
    if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
        echo "✓ Chrome closed gracefully"
        break
    fi
    echo "Waiting for Chrome to close... ($i/5)"
    sleep 1
done

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for zoom level verification..."

# Try primary profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
else
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
        echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    else
        echo "⚠ Warning: Preferences file not found in any known location"
        echo "Locations checked:"
        echo "  - /home/ga/.config/google-chrome-cdp/Default/Preferences"
        echo "  - /home/ga/.config/google-chrome/Default/Preferences"
    fi
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Also copy task URL for verifier reference
if [ -f /tmp/zoom_task_url.txt ]; then
    cp /tmp/zoom_task_url.txt "$VERIFY_DIR/" 2>/dev/null || true
fi

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"