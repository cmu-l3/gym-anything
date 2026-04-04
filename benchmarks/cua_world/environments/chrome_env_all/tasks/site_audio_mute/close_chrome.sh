#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site Audio Muting Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are processed
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Log tab title as well
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active Title: $ACTIVE_TITLE"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# CRITICAL: Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save Preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Give Chrome time to flush Preferences to disk
sleep 1

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."

# Try multiple possible Chrome profile locations
CHROME_PROFILE_LOCATIONS=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
    "/home/ga/.config/chromium/Default"
)

PREFS_EXPORTED=false

for CHROME_PROFILE in "${CHROME_PROFILE_LOCATIONS[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        echo "Found Preferences at: $CHROME_PROFILE/Preferences"
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        
        # Also copy to more specific name for this task
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_audio_mute.json
        
        echo "✓ Preferences exported to /tmp/chrome_preferences.json"
        
        # Log file size for debugging
        PREF_SIZE=$(stat -f%z "$CHROME_PROFILE/Preferences" 2>/dev/null || stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
        echo "  Preferences file size: $PREF_SIZE bytes"
        
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Preferences file in any standard location"
    echo "Checked locations:"
    for loc in "${CHROME_PROFILE_LOCATIONS[@]}"; do
        echo "  - $loc/Preferences"
    done
fi

# Create a verification marker file with task completion timestamp
date +%s > /tmp/audio_mute_task_completed.txt

echo "✅ Export complete"
echo "Preferences file ready for verification"