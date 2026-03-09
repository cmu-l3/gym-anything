#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Audio Muting Task Export: mute_noisy_tab@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture final tabs state via CDP
echo "Capturing final tab state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_final_tabs_raw.json 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' /tmp/chrome_final_tabs_raw.json > /tmp/chrome_final_tabs.json
    
    FINAL_TAB_COUNT=$(jq 'length' /tmp/chrome_final_tabs.json)
    echo "✓ Final state: $FINAL_TAB_COUNT page tab(s)"
    
    # Extract URLs for verification
    jq -r '.[] | .url' /tmp/chrome_final_tabs.json > /tmp/final_tab_urls.txt
    
    echo "Final tabs:"
    cat /tmp/final_tab_urls.txt
else
    echo "⚠ Warning: Failed to capture final CDP information"
    echo "[]" > /tmp/chrome_final_tabs.json
    touch /tmp/final_tab_urls.txt
fi

# Take a screenshot of the tab bar (shows speaker icons)
if command -v import &> /dev/null; then
    echo "Taking screenshot of tab bar..."
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    
    # Also take a cropped screenshot of just the tab bar (top 50 pixels)
    su - ga -c "DISPLAY=:1 import -window root -crop 1920x50+0+0 /tmp/tab_bar_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshots saved"
fi

# Gracefully close Chrome to save preferences (including muted sites)
echo "Closing Chrome to save muted sites preferences..."
pkill -TERM chrome 2>/dev/null || true
sleep 3

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences (contains muted sites)
echo "Exporting Chrome Preferences for muted sites verification..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from $CHROME_PROFILE"
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Preferences file"
fi

echo "✅ Export complete"
echo "Verification files:"
echo "  - /tmp/initial_tabs.json (initial state)"
echo "  - /tmp/chrome_final_tabs.json (final state)"
echo "  - /tmp/chrome_preferences.json (muted sites)"
echo "  - /tmp/audio_tab_url.txt (target audio URL)"