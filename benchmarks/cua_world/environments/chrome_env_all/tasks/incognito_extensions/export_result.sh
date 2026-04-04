#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Incognito Extensions Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture final state via CDP before closing
echo "Capturing Chrome state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_final_tabs.json 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Check if incognito window is open by looking at multiple contexts
    TAB_COUNT=$(jq '[.[] | select(.type == "page")] | length' /tmp/chrome_final_tabs.json)
    echo "Found $TAB_COUNT tab(s)"
    
    # Save tab URLs for debugging
    jq -r '[.[] | select(.type == "page")] | .[] | .url' /tmp/chrome_final_tabs.json > /tmp/final_urls.txt || true
fi

# Take final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Final screenshot saved"
fi

# Check for incognito window using wmctrl
echo "Checking for incognito window..."
if wmctrl -l | grep -i "incognito" > /tmp/incognito_window_check.txt 2>/dev/null; then
    echo "✓ Incognito window detected via wmctrl"
    echo "true" > /tmp/incognito_detected.txt
else
    echo "⚠ No incognito window title detected"
    echo "false" > /tmp/incognito_detected.txt
fi

# Gracefully close Chrome to ensure Preferences are written to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
    echo "✓ Preferences exported to /tmp/chrome_preferences.json"
    
    # Show file size for verification
    PREF_SIZE=$(stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
    echo "Preferences file size: $PREF_SIZE bytes"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any location"
        touch /tmp/chrome_preferences.json  # Create empty file to prevent errors
    fi
fi

# Ensure extension ID file is available
if [ -f /tmp/test_extension_id.txt ]; then
    echo "✓ Extension ID file available: $(cat /tmp/test_extension_id.txt)"
else
    echo "⚠ Extension ID file not found"
    echo "unknown" > /tmp/test_extension_id.txt
fi

# Copy extension ID to verification temp
cp /tmp/test_extension_id.txt /tmp/extension_id_export.txt 2>/dev/null || true

echo "✅ Export complete"
echo "Files available for verification:"
echo "  - /tmp/chrome_preferences.json"
echo "  - /tmp/test_extension_id.txt"
echo "  - /tmp/incognito_detected.txt"
echo "  - /tmp/chrome_final_tabs.json"