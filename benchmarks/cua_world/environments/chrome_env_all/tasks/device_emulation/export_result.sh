#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Device Emulation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/device_emulation_verification"
mkdir -p "$VERIFY_DIR"

# Capture full screen screenshot
echo "Capturing full screen screenshot..."
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/full_screen.png" 2>/dev/null || true
    echo "✓ Full screen screenshot saved"
fi

# Try to capture just the Chrome window
echo "Capturing Chrome window..."
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 import -window $wid $VERIFY_DIR/chrome_window.png" 2>/dev/null || true
    echo "✓ Chrome window screenshot saved"
fi

# Capture active tab information via CDP
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    
    # Try to extract viewport information if available in CDP
    # Note: This is best-effort, may not always be available
    jq -r '[.[] | select(.type == "page")][0] | {url, title, description}' "$VERIFY_DIR/chrome_tabs.json" > "$VERIFY_DIR/tab_info.json" 2>/dev/null || echo "{}" > "$VERIFY_DIR/tab_info.json"
fi

# Try to detect viewport dimensions from window geometry
echo "Detecting window geometry..."
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 xdotool getwindowgeometry $wid" > "$VERIFY_DIR/window_geometry.txt" 2>/dev/null || true
fi

# Get screen resolution for context
su - ga -c "DISPLAY=:1 xdpyinfo | grep dimensions" > "$VERIFY_DIR/screen_info.txt" 2>/dev/null || echo "Screen info not available" > "$VERIFY_DIR/screen_info.txt"

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files in: $VERIFY_DIR"
ls -lh "$VERIFY_DIR"/ 2>/dev/null || true