#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Homepage Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/homepage_verification"
mkdir -p "$VERIFY_DIR"

# Capture active tab URL via CDP before closing Chrome
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
    echo "✓ CDP tab information captured"
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/final_url.txt"
    echo "" > "$VERIFY_DIR/final_title.txt"
fi

# Take a screenshot before closing
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved"
fi

# Gracefully close Chrome to ensure Preferences are persisted to disk
echo "Closing Chrome to save preferences..."
pkill -f "google-chrome" || true
sleep 2

# Force kill if still running
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Preferences file from both possible locations
echo "Exporting Chrome Preferences..."

# Primary location (with CDP)
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/preferences_primary.json"
    echo "✓ Preferences exported from: $CHROME_PROFILE"
else
    echo "⚠ Preferences not found at: $CHROME_PROFILE"
fi

# Alternative location
ALT_PROFILE="/home/ga/.config/google-chrome/Default"
if [ -f "$ALT_PROFILE/Preferences" ]; then
    cp "$ALT_PROFILE/Preferences" "$VERIFY_DIR/preferences_alt.json"
    echo "✓ Preferences exported from: $ALT_PROFILE"
else
    echo "⚠ Preferences not found at: $ALT_PROFILE"
fi

# Copy to standard temp location for easier verifier access
cp "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# List exported files for debugging
echo ""
echo "Exported verification files:"
ls -lh "$VERIFY_DIR"/ 2>/dev/null || echo "No files in verification directory"

echo "✅ Export complete"