#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Download Location Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Wait a moment for any ongoing download to complete
echo "Waiting for potential download completion..."
sleep 3

# Focus Chrome window
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
fi

# Check Downloads page for recent downloads
echo "Checking for downloads via chrome://downloads..."
# Note: We don't navigate here as it might interfere, just log for debugging

# Create verification directory
VERIFY_DIR="/tmp/download_location_verification"
mkdir -p "$VERIFY_DIR"

# List contents of default Downloads folder
echo "Contents of default Downloads folder:"
DEFAULT_DOWNLOADS="/home/ga/Downloads"
if [ -d "$DEFAULT_DOWNLOADS" ]; then
    ls -lah "$DEFAULT_DOWNLOADS" || true
    find "$DEFAULT_DOWNLOADS" -name "test_download_file.txt" -mmin -5 > "$VERIFY_DIR/default_location_files.txt" 2>/dev/null || true
fi

# Search for custom download directories in home folder
echo "Searching for potential custom download directories..."
HOME_DIR="/home/ga"
find "$HOME_DIR" -maxdepth 1 -type d -not -name ".*" -not -name "Downloads" > "$VERIFY_DIR/home_directories.txt" 2>/dev/null || true

# Search for the test file in home directory
echo "Searching for test file in home directory..."
find "$HOME_DIR" -name "test_download_file.txt" -type f -mmin -10 > "$VERIFY_DIR/test_file_locations.txt" 2>/dev/null || true

if [ -s "$VERIFY_DIR/test_file_locations.txt" ]; then
    echo "Found test file at:"
    cat "$VERIFY_DIR/test_file_locations.txt"
else
    echo "⚠ Test file not found in recent downloads"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to $VERIFY_DIR/final_screenshot.png"
fi

# Close Chrome gracefully to ensure Preferences are saved
echo "Closing Chrome to save preferences..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" 2>/dev/null || true
sleep 0.5
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file for verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
    echo "✓ Preferences exported to $VERIFY_DIR/chrome_preferences.json"
    
    # Extract and display download directory setting
    DOWNLOAD_DIR=$(jq -r '.download.default_directory // "not_set"' "$VERIFY_DIR/chrome_preferences.json" 2>/dev/null)
    echo "Download directory in preferences: $DOWNLOAD_DIR"
    echo "$DOWNLOAD_DIR" > "$VERIFY_DIR/preferences_download_dir.txt"
else
    echo "⚠ Warning: Preferences file not found at $CHROME_PROFILE/Preferences"
    # Try alternative location
    ALT_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$ALT_PROFILE/Preferences" ]; then
        cp "$ALT_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
        echo "✓ Preferences exported from alternative location"
        DOWNLOAD_DIR=$(jq -r '.download.default_directory // "not_set"' "$VERIFY_DIR/chrome_preferences.json" 2>/dev/null)
        echo "$DOWNLOAD_DIR" > "$VERIFY_DIR/preferences_download_dir.txt"
    else
        echo "not_found" > "$VERIFY_DIR/preferences_download_dir.txt"
    fi
fi

# Copy all verification data to /tmp for easy access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"