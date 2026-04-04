#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Search Engine Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq sqlite3 || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# CRITICAL: Close Chrome gracefully to ensure Preferences file is written
echo "Closing Chrome to save preferences..."
pkill -TERM chrome || true
sleep 3

# Double-check Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 chrome || true
    sleep 2
fi

# Export Chrome Preferences file for verification
echo "Exporting Chrome Preferences file..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

PREFS_FOUND=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Found Preferences at: $CHROME_PROFILE/Preferences"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        PREFS_FOUND=true
        break
    fi
done

if [ "$PREFS_FOUND" = false ]; then
    echo "⚠ Warning: Could not find Chrome Preferences file"
    echo "Searched locations:"
    for loc in "${CHROME_PROFILES[@]}"; do
        echo "  - $loc/Preferences"
    done
else
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
    # Show file size for debugging
    ls -lh /tmp/chrome_preferences.json
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Also capture the current state via CDP if Chrome is still accessible
# (This won't work since we closed Chrome, but keep for consistency)
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    echo "CDP info captured"
fi

echo "✅ Export complete"