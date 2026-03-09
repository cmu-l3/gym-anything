#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Downloads Location Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Wait a moment for any in-progress downloads to complete
echo "Waiting for downloads to complete..."
sleep 3

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Stop the HTTP server
echo "Stopping test download server..."
if [ -f /tmp/download_server.pid ]; then
    HTTP_PID=$(cat /tmp/download_server.pid)
    kill $HTTP_PID 2>/dev/null || true
    rm -f /tmp/download_server.pid
    echo "✓ HTTP server stopped"
fi

# Export Chrome Preferences file for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_EXPORTED=false
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences.json
        echo "✓ Preferences exported from: $CHROME_PROFILE"
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Chrome Preferences file"
fi

# Check and document downloaded file status
echo "Checking download locations..."

# Check custom location
if [ -d "/home/ga/CustomDownloads" ]; then
    echo "✓ CustomDownloads directory exists"
    ls -lah /home/ga/CustomDownloads/ || true
    
    if [ -f "/home/ga/CustomDownloads/test_download.pdf" ]; then
        echo "✓ Test file found in CustomDownloads!"
        FILE_SIZE=$(stat -f "%z" /home/ga/CustomDownloads/test_download.pdf 2>/dev/null || stat -c "%s" /home/ga/CustomDownloads/test_download.pdf 2>/dev/null || echo "0")
        echo "  File size: $FILE_SIZE bytes"
        echo "custom_location_success" > /tmp/download_location_result.txt
    else
        echo "✗ Test file NOT found in CustomDownloads"
        echo "custom_location_missing_file" > /tmp/download_location_result.txt
    fi
else
    echo "✗ CustomDownloads directory does NOT exist"
    echo "custom_location_no_dir" > /tmp/download_location_result.txt
fi

# Check default location (should NOT be there)
if [ -f "/home/ga/Downloads/test_download.pdf" ]; then
    echo "⚠ Test file found in default Downloads folder (should be in CustomDownloads)"
    echo "default_location_found" > /tmp/download_location_result.txt
else
    echo "✓ Test file NOT in default Downloads folder (as expected)"
fi

# Create a summary file for verification
cat > /tmp/download_task_summary.json << EOF
{
  "custom_dir_exists": $([ -d "/home/ga/CustomDownloads" ] && echo "true" || echo "false"),
  "test_file_in_custom": $([ -f "/home/ga/CustomDownloads/test_download.pdf" ] && echo "true" || echo "false"),
  "test_file_in_default": $([ -f "/home/ga/Downloads/test_download.pdf" ] && echo "true" || echo "false"),
  "preferences_exported": $PREFS_EXPORTED
}
EOF

echo "✓ Task summary exported to /tmp/download_task_summary.json"
cat /tmp/download_task_summary.json

echo "✅ Export complete"