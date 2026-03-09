#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Notification Permission Control Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/notification_permission_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save permissions state..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_COPIED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/Preferences"
        echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
        PREFS_COPIED=true
        break
    fi
done

if [ "$PREFS_COPIED" = false ]; then
    echo "⚠ Warning: Preferences file not found in any known location"
fi

# Export History file for navigation verification
echo "Exporting Chrome History..."
HISTORY_COPIED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/History" ]; then
        cp "$CHROME_PROFILE/History" "$VERIFY_DIR/History"
        echo "✓ History exported from: $CHROME_PROFILE/History"
        HISTORY_COPIED=true
        break
    fi
done

if [ "$HISTORY_COPIED" = false ]; then
    echo "⚠ Warning: History file not found in any known location"
fi

# Copy verification files to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Stop the HTTP server
if [ -f /tmp/notification_server.pid ]; then
    kill $(cat /tmp/notification_server.pid) 2>/dev/null || true
    rm /tmp/notification_server.pid
fi
lsof -ti:8000 | xargs kill -9 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"
ls -lh "$VERIFY_DIR" || true