#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome DevTools Local CSS Override Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq rsync || true

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
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Gracefully close Chrome to ensure DevTools state and overrides are saved
echo "Closing Chrome to save DevTools configuration and overrides..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export chrome_overrides directory to temporary location for verification
echo "Exporting chrome_overrides directory..."
OVERRIDE_DIR="/home/ga/chrome_overrides"
TEMP_EXPORT_DIR="/tmp/chrome_overrides_export"

if [ -d "$OVERRIDE_DIR" ]; then
    # Create temporary export directory
    mkdir -p "$TEMP_EXPORT_DIR"
    
    # Copy entire override directory structure recursively
    cp -r "$OVERRIDE_DIR"/* "$TEMP_EXPORT_DIR/" 2>/dev/null || true
    
    # List contents for debugging
    echo "Override directory contents:"
    find "$OVERRIDE_DIR" -type f 2>/dev/null | head -20 || echo "No files found"
    
    echo "✓ Override directory copied to: $TEMP_EXPORT_DIR"
    
    # Create a manifest file with directory structure
    find "$OVERRIDE_DIR" -type f > /tmp/override_manifest.txt 2>/dev/null || true
    echo "✓ Override manifest created: /tmp/override_manifest.txt"
else
    echo "⚠ Warning: Override directory not found at $OVERRIDE_DIR"
    mkdir -p "$TEMP_EXPORT_DIR"
    echo "none" > "$TEMP_EXPORT_DIR/no_overrides.txt"
fi

# Export Chrome Preferences for DevTools configuration verification
echo "Exporting Chrome Preferences..."
CHROME_PROFILES=(
    "/home/ga/.config/google-chrome-cdp/Default"
    "/home/ga/.config/google-chrome/Default"
)

PREFS_EXPORTED=false
for PROFILE in "${CHROME_PROFILES[@]}"; do
    if [ -f "$PROFILE/Preferences" ]; then
        cp "$PROFILE/Preferences" /tmp/chrome_preferences.json 2>/dev/null || true
        echo "✓ Preferences exported from: $PROFILE"
        PREFS_EXPORTED=true
        break
    fi
done

if [ "$PREFS_EXPORTED" = false ]; then
    echo "⚠ Warning: Could not find Chrome Preferences file"
fi

# Create verification summary
cat > /tmp/override_verification_summary.txt << EOF
CSS Override Task Export Summary
================================
Export Time: $(date)
Override Directory: $OVERRIDE_DIR
Override Files Count: $(find "$OVERRIDE_DIR" -type f 2>/dev/null | wc -l)
Preferences Exported: $PREFS_EXPORTED

Directory Structure:
$(find "$OVERRIDE_DIR" -type d 2>/dev/null | sed 's|^|  |' || echo "  (none)")

Files Found:
$(find "$OVERRIDE_DIR" -type f 2>/dev/null | sed 's|^|  |' || echo "  (none)")
EOF

echo ""
echo "=== Verification Summary ==="
cat /tmp/override_verification_summary.txt

echo "✅ Export complete"