#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download Location Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    
    # Check if user is on settings page
    if [[ "$ACTIVE_URL" == *"chrome://settings"* ]]; then
        echo "✓ Agent navigated to Chrome settings"
    fi
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || pkill -f "chromium" || true
sleep 2

# Double-check Chrome is fully closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome still running, force killing..."
    pkill -9 -f "google-chrome" || pkill -9 -f "chromium" || true
    sleep 1
fi

echo "✓ Chrome closed successfully"

# Export Preferences file to temporary location for verification
echo "Exporting Chrome Preferences file..."

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_export.json
    echo "✓ Preferences exported from: $CHROME_PROFILE/Preferences"
    
    # Extract and display download location for debugging
    DL_LOCATION=$(jq -r '.download.default_directory // "not_set"' /tmp/chrome_preferences_export.json 2>/dev/null || echo "parse_error")
    echo "Download location in Preferences: $DL_LOCATION"
    
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    
    # Try alternative Chrome profile location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_export.json
        echo "✓ Preferences exported from alternative location: $ALT_PROFILE/Preferences"
        
        DL_LOCATION=$(jq -r '.download.default_directory // "not_set"' /tmp/chrome_preferences_export.json 2>/dev/null || echo "parse_error")
        echo "Download location in Preferences: $DL_LOCATION"
    else
        echo "✗ Could not find Preferences file in any known location"
        
        # Create empty JSON to prevent verification errors
        echo "{}" > /tmp/chrome_preferences_export.json
    fi
fi

# Verify the secondary storage directory still exists
if [ -d "/home/ga/secondary_storage/downloads" ]; then
    echo "✓ Secondary storage directory exists and is accessible"
    ls -la /home/ga/secondary_storage/downloads/ || true
else
    echo "⚠ Secondary storage directory not found"
fi

# Save verification metadata
cat > /tmp/download_location_metadata.json << EOF
{
  "task_id": "download_location_emergency@1",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "expected_location": "/home/ga/secondary_storage/downloads",
  "default_location": "/home/ga/Downloads",
  "secondary_storage_exists": $([ -d "/home/ga/secondary_storage/downloads" ] && echo "true" || echo "false")
}
EOF

echo "✓ Verification metadata saved to /tmp/download_location_metadata.json"

echo "✅ Export complete"
echo "Files exported for verification:"
echo "  - /tmp/chrome_preferences_export.json (Chrome Preferences)"
echo "  - /tmp/download_location_metadata.json (Task metadata)"
echo "  - /tmp/final_url.txt (Final active tab URL)"
echo "  - /tmp/final_screenshot.png (Final screenshot)"