#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Safe Browsing Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL for verification context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a screenshot before closing Chrome (for debugging)
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
# This is CRITICAL for preferences-based tasks
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "Verifying Chrome is stopped..."
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "✓ Chrome successfully stopped"
else
    echo "⚠ Warning: Chrome may still be running"
fi

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Try primary profile location
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_safebrowsing.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    ls -lh "$CHROME_PROFILE/Preferences"
    
    # Display Safe Browsing settings for debugging
    echo "Safe Browsing configuration in Preferences:"
    jq -r '.safebrowsing // "safebrowsing section not found"' /tmp/chrome_preferences_safebrowsing.json 2>/dev/null || echo "Could not parse safebrowsing settings"
    
elif [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_safebrowsing.json
    echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
    ls -lh "$ALT_PROFILE/Preferences"
else
    echo "✗ Warning: Preferences file not found in any expected location"
    echo "  Tried: $CHROME_PROFILE/Preferences"
    echo "  Tried: $ALT_PROFILE/Preferences"
    
    # Create empty file to prevent verifier errors
    echo "{}" > /tmp/chrome_preferences_safebrowsing.json
fi

# Create a verification metadata file with timestamps
cat > /tmp/safe_browsing_export_metadata.json << EOF
{
  "export_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "chrome_stopped": $(pgrep -f "chrome" > /dev/null && echo "false" || echo "true"),
  "preferences_exported": $([ -f /tmp/chrome_preferences_safebrowsing.json ] && echo "true" || echo "false"),
  "preferences_size": $(stat -f%z /tmp/chrome_preferences_safebrowsing.json 2>/dev/null || stat -c%s /tmp/chrome_preferences_safebrowsing.json 2>/dev/null || echo "0")
}
EOF

echo "✅ Export complete"
echo "Verification files ready at /tmp/"