#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Accessibility Font Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for debugging
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url_fonts.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_fonts.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_fonts.png"
fi

# IMPORTANT: Kill Chrome to ensure Preferences are saved to disk
# Chrome saves preferences periodically and on exit
echo "Stopping Chrome to ensure preferences are persisted..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "✓ Chrome stopped, preferences should be written to disk"

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."

# Try primary location first
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_fonts.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    ls -lh "$CHROME_PROFILE/Preferences"
else
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_fonts.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
        ls -lh "$ALT_PROFILE/Preferences"
    else
        echo "⚠ Warning: Preferences file not found in either location"
        echo "  - Tried: $CHROME_PROFILE/Preferences"
        echo "  - Tried: $ALT_PROFILE/Preferences"
        
        # List what's available for debugging
        echo "Available files in chrome-cdp profile:"
        ls -la "$CHROME_PROFILE/" 2>/dev/null || echo "  Profile directory not found"
        
        echo "Available files in chrome profile:"
        ls -la "$ALT_PROFILE/" 2>/dev/null || echo "  Profile directory not found"
    fi
fi

# Extract font settings for quick verification (debug info)
if [ -f /tmp/chrome_preferences_fonts.json ]; then
    echo ""
    echo "Current font settings in Preferences:"
    jq -r '.webkit.webprefs | "  default_font_size: \(.default_font_size // "not set")\n  minimum_font_size: \(.minimum_font_size // "not set")\n  default_fixed_font_size: \(.default_fixed_font_size // "not set")"' /tmp/chrome_preferences_fonts.json 2>/dev/null || echo "  Could not extract font settings"
fi

echo ""
echo "✅ Export complete"
echo "Verification files ready in /tmp/"