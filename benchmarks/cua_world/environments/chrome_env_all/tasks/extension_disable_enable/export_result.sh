#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Management Task Export: extension_disable_enable@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure changes are saved
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture current URL to see if agent navigated to extensions page
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    if [[ "$ACTIVE_URL" == *"chrome://extensions"* ]]; then
        echo "✓ Agent navigated to chrome://extensions/"
    else
        echo "⚠ Agent is not on extensions page"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are flushed to disk
echo "Closing Chrome to save extension state..."
pkill -SIGTERM chrome || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for extension state verification
echo "Exporting Chrome Preferences for extension state verification..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_export.json"
    
    # Extract extension information for debugging
    if command -v jq &> /dev/null; then
        echo ""
        echo "Extension states in Preferences:"
        jq -r '.extensions.settings | to_entries[] | "\(.key): state=\(.value.state), name=\(.value.manifest.name // "unknown")"' \
            /tmp/chrome_preferences_export.json 2>/dev/null || echo "(Could not parse extension info)"
    fi
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any expected location"
        # Create empty JSON to prevent verifier errors
        echo '{"extensions": {"settings": {}}}' > /tmp/chrome_preferences_export.json
    fi
fi

# Copy extension ID file if it exists
if [ -f "/tmp/test_extension_id.txt" ]; then
    cp /tmp/test_extension_id.txt /tmp/test_extension_id_export.txt
    echo "✓ Extension ID exported"
fi

echo ""
echo "✅ Export complete"
echo "Files available for verification:"
echo "  - /tmp/chrome_preferences_export.json (extension states)"
echo "  - /tmp/test_extension_id_export.txt (test extension ID)"
echo "  - /tmp/final_url.txt (final active tab URL)"
echo "  - /tmp/final_screenshot.png (final screenshot)"