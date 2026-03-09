#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Font Customization Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any pending changes are saved
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    if [[ "$ACTIVE_URL" == *"chrome://settings/fonts"* ]]; then
        echo "✓ Agent remained on font settings page"
    else
        echo "⚠ Note: Agent navigated away from font settings (URL: $ACTIVE_URL)"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Wait briefly to ensure any pending preference writes complete
sleep 1

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save font preferences..."

# Try graceful shutdown first (Ctrl+Q)
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+q" 2>/dev/null || true
sleep 2

# If Chrome is still running, use pkill
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, using pkill..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "✓ Chrome closed"

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."

# Try multiple possible Chrome profile locations
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Found Preferences at: $CHROME_PROFILE/Preferences"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_fonts.json
        
        # Also save size for verification
        PREFS_SIZE=$(stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "0")
        echo "Preferences file size: $PREFS_SIZE bytes"
        echo "$PREFS_SIZE" > /tmp/prefs_size.txt
        
        # Extract and log font settings for debugging
        if command -v jq &> /dev/null; then
            echo "Exported font settings:"
            jq -r '.webkit.webprefs.fonts // "No font settings found"' /tmp/chrome_preferences_fonts.json 2>/dev/null | head -20 || echo "Could not extract font settings"
        fi
        
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = true ]; then
    echo "✓ Preferences exported to /tmp/chrome_preferences_fonts.json"
else
    echo "✗ Warning: Could not find Preferences file in any known location"
    
    # Create empty marker file to help verifier
    echo '{"error": "Preferences file not found"}' > /tmp/chrome_preferences_fonts.json
    
    # List directories for debugging
    echo "Chrome config directories:"
    ls -la /home/ga/.config/ 2>/dev/null | grep -i chrome || echo "No Chrome directories found"
fi

# Create verification metadata
cat > /tmp/font_config_metadata.json << EOF
{
  "task_completed_at": "$(date -Iseconds)",
  "preferences_exported": $PREFS_EXPORTED,
  "chrome_closed": true
}
EOF

echo "✅ Export complete"
echo "Files exported to /tmp/ for verification:"
echo "  - /tmp/chrome_preferences_fonts.json"
echo "  - /tmp/final_url.txt"
echo "  - /tmp/font_config_metadata.json"