#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Experimental Flags Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
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
else
    echo "⚠ Warning: Could not capture CDP data"
    echo "unknown" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are written to disk
echo "Closing Chrome to save configuration changes..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

echo "Chrome closed, preferences should be saved to disk"

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences for verification..."

# Try multiple possible locations for Chrome profile
EXPORT_SUCCESS=false

# Location 1: Default profile
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_flags.json
    echo "✓ Preferences exported from: $CHROME_PROFILE"
    EXPORT_SUCCESS=true
fi

# Location 2: CDP profile (alternative)
if [ "$EXPORT_SUCCESS" = false ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_flags.json
        echo "✓ Preferences exported from: $CHROME_PROFILE (CDP)"
        EXPORT_SUCCESS=true
    fi
fi

# Location 3: Alternative naming
if [ "$EXPORT_SUCCESS" = false ]; then
    CHROME_PROFILE="/home/ga/.config/chromium/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_flags.json
        echo "✓ Preferences exported from: $CHROME_PROFILE (Chromium)"
        EXPORT_SUCCESS=true
    fi
fi

if [ "$EXPORT_SUCCESS" = false ]; then
    echo "⚠ Warning: Could not find Preferences file in any known location"
    echo "Searched locations:"
    echo "  - /home/ga/.config/google-chrome/Default/Preferences"
    echo "  - /home/ga/.config/google-chrome-cdp/Default/Preferences"
    echo "  - /home/ga/.config/chromium/Default/Preferences"
    
    # Create empty JSON for verifier to handle gracefully
    echo "{}" > /tmp/chrome_preferences_flags.json
else
    # Show file info for debugging
    ls -lh /tmp/chrome_preferences_flags.json
fi

# Also export Local State if it exists (some flags stored there)
if [ -f "/home/ga/.config/google-chrome/Local State" ]; then
    cp "/home/ga/.config/google-chrome/Local State" /tmp/chrome_local_state.json
    echo "✓ Local State exported"
fi

# Copy backup for comparison
if [ -f "/tmp/preferences_backup.json" ]; then
    echo "✓ Backup preferences available for comparison"
fi

echo "✅ Export complete"
echo "Verification files ready at /tmp/"