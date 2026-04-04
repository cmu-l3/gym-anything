#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Font Family Customization Task Export ==="

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
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if agent was in settings
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent was in Chrome settings"
    else
        echo "⚠ Agent's final URL was not in settings: $ACTIVE_URL"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save font preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for font family verification
echo "Exporting Chrome Preferences for verification..."

# Try primary location (chrome-cdp profile)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_fonts.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_fonts.json"
    
    # Show file size for debugging
    PREFS_SIZE=$(stat -f%z "$CHROME_PROFILE/Preferences" 2>/dev/null || stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
    echo "  Preferences file size: $PREFS_SIZE bytes"
else
    echo "⚠ Preferences not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location (standard Chrome profile)
    CHROME_PROFILE_ALT="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE_ALT/Preferences" ]; then
        cp "$CHROME_PROFILE_ALT/Preferences" /tmp/chrome_preferences_fonts.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any location"
        echo "  Searched locations:"
        echo "    - $CHROME_PROFILE/Preferences"
        echo "    - $CHROME_PROFILE_ALT/Preferences"
    fi
fi

# Extract and display webkit.webprefs.fonts section for quick debugging
if [ -f /tmp/chrome_preferences_fonts.json ]; then
    echo ""
    echo "Extracting font configuration from Preferences..."
    
    # Try to extract fonts section using jq
    if command -v jq &> /dev/null; then
        FONTS_CONFIG=$(jq -r '.webkit.webprefs.fonts // "fonts config not found"' /tmp/chrome_preferences_fonts.json 2>/dev/null || echo "extraction failed")
        if [[ "$FONTS_CONFIG" != "fonts config not found" ]] && [[ "$FONTS_CONFIG" != "extraction failed" ]] && [[ "$FONTS_CONFIG" != "null" ]]; then
            echo "Font configuration detected:"
            echo "$FONTS_CONFIG" | head -20
        else
            echo "⚠ Font configuration structure not found or empty in Preferences"
            
            # Try alternative flat structure
            STANDARD_FONT=$(jq -r '.webkit.webprefs.standard_font_family // "not set"' /tmp/chrome_preferences_fonts.json 2>/dev/null || echo "extraction failed")
            if [[ "$STANDARD_FONT" != "not set" ]] && [[ "$STANDARD_FONT" != "extraction failed" ]]; then
                echo "Found flat font structure:"
                echo "  standard_font_family: $STANDARD_FONT"
            fi
        fi
    fi
fi

echo ""
echo "✅ Export complete"
echo "Verification will check that font families were customized in Preferences."