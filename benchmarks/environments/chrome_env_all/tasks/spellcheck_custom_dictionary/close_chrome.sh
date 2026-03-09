#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Spell Check Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time to ensure settings are synced
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for additional verification
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

# Gracefully close Chrome to ensure settings and dictionary are persisted to disk
echo "Closing Chrome to save spell check configuration and custom dictionary..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Export Chrome configuration files to temporary location for verification
echo "Exporting Chrome configuration files..."

# Try primary Chrome profile location
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Determine which profile directory to use
if [ -d "$CHROME_PROFILE" ]; then
    PROFILE_DIR="$CHROME_PROFILE"
    echo "Using primary profile: $PROFILE_DIR"
elif [ -d "$ALT_PROFILE" ]; then
    PROFILE_DIR="$ALT_PROFILE"
    echo "Using alternative profile: $ALT_PROFILE"
else
    echo "⚠ Warning: Could not find Chrome profile directory"
    PROFILE_DIR=""
fi

# Export Preferences file
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/Preferences" ]; then
    cp "$PROFILE_DIR/Preferences" /tmp/chrome_preferences_spellcheck.json
    echo "✓ Preferences exported to /tmp/chrome_preferences_spellcheck.json"
    
    # Extract and display spell check settings
    SPELLCHECK_ENABLED=$(jq -r '.browser.enable_spellchecking // false' "$PROFILE_DIR/Preferences" 2>/dev/null)
    SPELL_LANGUAGES=$(jq -r '.spellcheck.dictionaries // []' "$PROFILE_DIR/Preferences" 2>/dev/null)
    echo "  Spell check enabled: $SPELLCHECK_ENABLED"
    echo "  Spell check languages: $SPELL_LANGUAGES"
else
    echo "⚠ Warning: Preferences file not found"
fi

# Export Custom Dictionary file
DICT_FILE="Custom Dictionary.txt"
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/$DICT_FILE" ]; then
    cp "$PROFILE_DIR/$DICT_FILE" /tmp/chrome_custom_dictionary.txt
    echo "✓ Custom Dictionary exported to /tmp/chrome_custom_dictionary.txt"
    
    # Display dictionary contents
    WORD_COUNT=$(wc -l < "$PROFILE_DIR/$DICT_FILE" 2>/dev/null || echo "0")
    echo "  Custom dictionary word count: $WORD_COUNT"
    
    if [ "$WORD_COUNT" -gt 0 ] && [ "$WORD_COUNT" -le 10 ]; then
        echo "  Custom words:"
        cat "$PROFILE_DIR/$DICT_FILE" | head -10 | while read word; do
            echo "    - $word"
        done
    fi
else
    echo "⚠ Warning: Custom Dictionary file not found"
    # Create empty file to prevent verification errors
    touch /tmp/chrome_custom_dictionary.txt
fi

# Export both profile locations for verifier to try
echo "Saving profile paths for verifier..."
echo "$CHROME_PROFILE" > /tmp/chrome_profile_primary.txt
echo "$ALT_PROFILE" > /tmp/chrome_profile_alt.txt

echo "✅ Export complete"
echo "Files ready for verification:"
echo "  - /tmp/chrome_preferences_spellcheck.json"
echo "  - /tmp/chrome_custom_dictionary.txt"