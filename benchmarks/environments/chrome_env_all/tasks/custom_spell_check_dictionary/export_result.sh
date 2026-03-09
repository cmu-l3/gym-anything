#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Custom Spell Check Dictionary Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure changes are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
fi

# Give Chrome a moment to autosave any pending changes
sleep 1

# Gracefully close Chrome to ensure custom dictionary is persisted to disk
echo "Closing Chrome to save custom dictionary..."
pkill -f "google-chrome" || true
sleep 2

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export custom dictionary file to temporary location for verification
echo "Exporting Chrome custom dictionary..."

# Try both possible profile locations
DICT_EXPORTED=false

# Location 1: CDP profile (google-chrome-cdp)
DICT_FILE_CDP="/home/ga/.config/google-chrome-cdp/Default/Custom Dictionary.txt"
if [ -f "$DICT_FILE_CDP" ]; then
    cp "$DICT_FILE_CDP" /tmp/custom_dictionary_export.txt
    echo "✓ Custom dictionary exported from CDP profile to /tmp/custom_dictionary_export.txt"
    ls -lh "$DICT_FILE_CDP"
    echo "Dictionary contents:"
    cat "$DICT_FILE_CDP" | head -20
    DICT_EXPORTED=true
fi

# Location 2: Standard profile (google-chrome)
DICT_FILE_STD="/home/ga/.config/google-chrome/Default/Custom Dictionary.txt"
if [ -f "$DICT_FILE_STD" ]; then
    # If we haven't exported yet, or if this file is newer, use it
    if [ "$DICT_EXPORTED" = false ] || [ "$DICT_FILE_STD" -nt "$DICT_FILE_CDP" ]; then
        cp "$DICT_FILE_STD" /tmp/custom_dictionary_export.txt
        echo "✓ Custom dictionary exported from standard profile to /tmp/custom_dictionary_export.txt"
        ls -lh "$DICT_FILE_STD"
        echo "Dictionary contents:"
        cat "$DICT_FILE_STD" | head -20
        DICT_EXPORTED=true
    fi
fi

if [ "$DICT_EXPORTED" = false ]; then
    echo "⚠ Warning: Custom Dictionary.txt not found in any known location"
    echo "Checked locations:"
    echo "  - $DICT_FILE_CDP"
    echo "  - $DICT_FILE_STD"
    
    # Create empty file to prevent verifier errors
    touch /tmp/custom_dictionary_export.txt
    echo "Created empty placeholder file"
else
    echo "✅ Dictionary export successful"
fi

# Also save both file locations to temp for verifier to try
echo "$DICT_FILE_CDP" > /tmp/dict_location_cdp.txt
echo "$DICT_FILE_STD" > /tmp/dict_location_std.txt

echo "✅ Export complete"