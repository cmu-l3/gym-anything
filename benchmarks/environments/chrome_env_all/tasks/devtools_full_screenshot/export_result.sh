#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Full Page Screenshot Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Give a moment for any ongoing download to complete
echo "Waiting for screenshot download to complete..."
sleep 2

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# List Downloads folder contents for debugging
echo "Contents of Downloads folder:"
ls -lh /home/ga/Downloads/ 2>/dev/null || echo "Downloads folder is empty or doesn't exist"

# Copy Downloads folder metadata to temp for verification
echo "Exporting Downloads folder information..."
if [ -d "/home/ga/Downloads" ]; then
    # Create a manifest of all files with timestamps
    find /home/ga/Downloads -type f -name "*.png" -printf "%T@ %p %s\n" 2>/dev/null | sort -rn > /tmp/downloads_manifest.txt || true
    echo "✓ Downloads manifest created"
fi

# Take a final screenshot of the desktop for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_desktop_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved to /tmp/final_desktop_screenshot.png"
fi

# Gracefully close Chrome to ensure downloads are finalized
echo "Closing Chrome..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "✅ Export complete"
echo "Verification will check for screenshot in Downloads folder"