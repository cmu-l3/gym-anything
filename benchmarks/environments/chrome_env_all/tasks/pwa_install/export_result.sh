#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome PWA Installation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/pwa_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP for additional verification
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Gracefully close Chrome to ensure all data is persisted to disk
echo "Closing Chrome to save app data..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome Preferences file
echo "Exporting Chrome Preferences..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/Preferences.json"
        echo "✓ Preferences exported from: $CHROME_PROFILE"
        break
    fi
done

if [ ! -f "$VERIFY_DIR/Preferences.json" ]; then
    echo "⚠ Warning: Could not find Preferences file"
fi

# Look for desktop shortcuts
echo "Searching for desktop shortcuts..."
DESKTOP_LOCATIONS=(
    "/home/ga/Desktop"
    "/home/ga/.local/share/applications"
)

for location in "${DESKTOP_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        echo "Checking: $location"
        # Look for .desktop files created recently (last 10 minutes)
        find "$location" -name "*.desktop" -type f -mmin -10 2>/dev/null | while read -r desktop_file; do
            echo "Found desktop file: $desktop_file"
            cp "$desktop_file" "$VERIFY_DIR/$(basename "$desktop_file")" 2>/dev/null || true
        done
    fi
done

# Check Web Applications directory
echo "Checking Web Applications directory..."
for CHROME_PROFILE in "${CHROME_PROFILES[@]}"; do
    WEB_APPS_DIR="$CHROME_PROFILE/Web Applications"
    if [ -d "$WEB_APPS_DIR" ]; then
        echo "Found Web Applications directory: $WEB_APPS_DIR"
        # List manifest files
        find "$WEB_APPS_DIR" -name "Manifest*.json" -type f 2>/dev/null | while read -r manifest; do
            echo "Found manifest: $manifest"
            cp "$manifest" "$VERIFY_DIR/$(basename "$manifest")" 2>/dev/null || true
        done
        # Create a marker file indicating the directory exists
        echo "$WEB_APPS_DIR" > "$VERIFY_DIR/web_apps_dir.txt"
        break
    fi
done

# Stop the HTTP server
echo "Stopping HTTP server..."
pkill -f "python3.*8080" || true

# Copy all verification files to /tmp for easy access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"