#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Download Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
else
    echo "about:blank" > /tmp/final_url.txt
fi

# Take a screenshot before closing Chrome
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

# Export Chrome Preferences file to temporary location for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" /tmp/chrome_preferences_download.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_download.json"
    
    # Extract and display download settings for debugging
    DOWNLOAD_DIR=$(jq -r '.download.default_directory // "not set"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "not set")
    AUTO_OPEN=$(jq -r '.download.extensions_to_open // "not set"' "$CHROME_PROFILE/Preferences" 2>/dev/null || echo "not set")
    echo "Download directory: $DOWNLOAD_DIR"
    echo "Auto-open extensions: $AUTO_OPEN"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" /tmp/chrome_preferences_download.json
        echo "✓ Preferences exported from alternative location"
    else
        echo "✗ Could not find Preferences file in any known location"
    fi
fi

# Check if MyDownloads directory was created
echo "Checking for MyDownloads directory..."
if [ -d "/home/ga/MyDownloads" ]; then
    echo "✓ MyDownloads directory exists"
    ls -lah /home/ga/MyDownloads > /tmp/mydownloads_listing.txt 2>&1 || true
    # Record directory info for verification
    stat /home/ga/MyDownloads > /tmp/mydownloads_stat.txt 2>&1 || true
else
    echo "⚠ MyDownloads directory not found"
    echo "not_found" > /tmp/mydownloads_listing.txt
fi

# List Downloads directory for comparison
echo "Listing Downloads directory..."
ls -lah /home/ga/Downloads > /tmp/downloads_listing.txt 2>&1 || true

# Create a summary file for verifier
cat > /tmp/download_task_summary.txt << EOF
Task: Configure Chrome download location
Timestamp: $(date)
MyDownloads exists: $([ -d "/home/ga/MyDownloads" ] && echo "yes" || echo "no")
Download directory in Preferences: ${DOWNLOAD_DIR:-unknown}
Auto-open extensions: ${AUTO_OPEN:-unknown}
Active URL at task end: ${ACTIVE_URL:-unknown}
EOF

echo "✅ Export complete"
echo "Verification files created:"
echo "  - /tmp/chrome_preferences_download.json (Preferences file)"
echo "  - /tmp/mydownloads_listing.txt (Directory listing)"
echo "  - /tmp/download_task_summary.txt (Task summary)"