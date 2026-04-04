#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Site-Specific Image Blocking Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
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
    
    # Log whether agent visited example.com
    if [[ "$ACTIVE_URL" == *"example.com"* ]]; then
        echo "✓ Agent is/was on example.com"
    else
        echo "⚠ Agent is not on example.com (current: $ACTIVE_URL)"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save site settings..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

# Try primary profile location
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_export.json"
    
    # Log file size for debugging
    FILE_SIZE=$(stat -f%z "$CHROME_PROFILE/Preferences" 2>/dev/null || stat -c%s "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "unknown")
    echo "  File size: $FILE_SIZE bytes"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Error: Could not find Preferences file in any known location"
        # Create empty file to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Create a summary file for quick reference
echo "Creating verification summary..."
cat > /tmp/verification_summary.txt << EOF
Task: block_images_site@1
Timestamp: $(date)
Active URL: ${ACTIVE_URL:-unknown}
Preferences exported: $([ -f /tmp/chrome_preferences_export.json ] && echo "yes" || echo "no")
EOF

echo "✅ Export complete"
echo "Verification files available at:"
echo "  - /tmp/chrome_preferences_export.json"
echo "  - /tmp/final_url.txt"
echo "  - /tmp/final_screenshot.png"
echo "  - /tmp/verification_summary.txt"