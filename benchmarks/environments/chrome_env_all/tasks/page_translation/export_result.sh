#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Translation Task Export: page_translation@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary directory for verification data
VERIFY_DIR="/tmp/translation_verification"
mkdir -p "$VERIFY_DIR"

# Capture final tab state via CDP
echo "Capturing final page state via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/final_tab_state.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Extract final title and URL
    FINAL_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/final_tab_state.json")
    FINAL_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/final_tab_state.json")
    
    echo "Final page title: $FINAL_TITLE"
    echo "Final page URL: $FINAL_URL"
    
    # Save extracted info to separate files for easier verification
    echo "$FINAL_TITLE" > "$VERIFY_DIR/final_title.txt"
    echo "$FINAL_URL" > "$VERIFY_DIR/final_url.txt"
    
    # Check if title indicates English content
    if echo "$FINAL_TITLE" | grep -qi "artificial intelligence"; then
        echo "✓ Title appears to be in English"
    elif echo "$FINAL_TITLE" | grep -qi "inteligencia"; then
        echo "⚠ Warning: Title still appears to be in Spanish"
    fi
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "" > "$VERIFY_DIR/final_title.txt"
    echo "" > "$VERIFY_DIR/final_url.txt"
fi

# Copy initial state if it exists for comparison
if [ -f "/tmp/initial_tab_state.json" ]; then
    cp /tmp/initial_tab_state.json "$VERIFY_DIR/" || true
    INITIAL_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/initial_tab_state.json 2>/dev/null || echo "")
    echo "$INITIAL_TITLE" > "$VERIFY_DIR/initial_title.txt"
    echo "✓ Copied initial state for comparison"
fi

# Try to capture Chrome preferences (contains translation settings)
echo "Attempting to capture Chrome preferences..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json" 2>/dev/null || true
    echo "✓ Preferences captured"
else
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json" 2>/dev/null || true
        echo "✓ Preferences captured from alternative location"
    fi
fi

# Take a final screenshot for visual debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "✓ Screenshot saved"
fi

# Copy verification files to standard /tmp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo ""
echo "✅ Export complete"
echo "Verification data saved to: $VERIFY_DIR"
echo ""
echo "Summary:"
if [ -f "$VERIFY_DIR/initial_title.txt" ] && [ -f "$VERIFY_DIR/final_title.txt" ]; then
    INIT_TITLE=$(cat "$VERIFY_DIR/initial_title.txt")
    FIN_TITLE=$(cat "$VERIFY_DIR/final_title.txt")
    echo "  Initial title: ${INIT_TITLE:0:60}..."
    echo "  Final title:   ${FIN_TITLE:0:60}..."
fi