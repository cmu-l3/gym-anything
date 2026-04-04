#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Page Rendering Debug Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq imagemagick || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/page_rendering_verification"
mkdir -p "$VERIFY_DIR"

echo "Capturing final state..."

# Take final screenshot
echo "Taking final screenshot..."
su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/screenshot_final.png" 2>/dev/null || true

# Capture active tab information via CDP
echo "Capturing tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    echo "✓ CDP tab information captured"
    
    # Extract active tab URL
    jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json" > "$VERIFY_DIR/final_url.txt"
    
    # Check if DevTools is mentioned in any tab
    DEVTOOLS_OPEN=$(jq '[.[] | select(.url | contains("devtools://"))] | length' "$VERIFY_DIR/chrome_tabs.json")
    echo "devtools_tabs=$DEVTOOLS_OPEN" > "$VERIFY_DIR/devtools_state.txt"
else
    echo "⚠ Warning: Could not capture CDP information"
fi

# Try to get console log info via CDP (if available)
echo "Attempting to capture console state..."
# Note: This is a simplified approach - full console log capture requires more complex CDP interaction
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    # Get the first page tab's WebSocket debugger URL
    DEBUGGER_URL=$(jq -r '[.[] | select(.type == "page")][0].webSocketDebuggerUrl // ""' "$VERIFY_DIR/chrome_tabs.json")
    if [ -n "$DEBUGGER_URL" ]; then
        echo "debugger_url=$DEBUGGER_URL" > "$VERIFY_DIR/cdp_info.txt"
    fi
fi

# Export Chrome Preferences to check DevTools settings and cache settings
echo "Exporting Chrome Preferences..."
pkill -STOP chrome 2>/dev/null || true  # Pause Chrome to ensure Preferences are written
sleep 1

CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ -f "$CHROME_PROFILE/Preferences" ]; then
    cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
    echo "✓ Preferences exported"
else
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
    if [ -f "$CHROME_PROFILE/Preferences" ]; then
        cp "$CHROME_PROFILE/Preferences" "$VERIFY_DIR/chrome_preferences.json"
        echo "✓ Preferences exported from alternative location"
    else
        echo "⚠ Preferences file not found"
        echo "{}" > "$VERIFY_DIR/chrome_preferences.json"
    fi
fi

pkill -CONT chrome 2>/dev/null || true  # Resume Chrome

# Check if CSS file was accessed (check file access time)
echo "Checking CSS file access..."
TEST_PAGE_DIR="/home/ga/Documents/debug_test"
if [ -f "$TEST_PAGE_DIR/styles.css" ]; then
    stat "$TEST_PAGE_DIR/styles.css" > "$VERIFY_DIR/css_file_stat.txt" 2>&1
    CSS_ACCESS_TIME=$(stat -c %X "$TEST_PAGE_DIR/styles.css" 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - CSS_ACCESS_TIME))
    echo "css_accessed_seconds_ago=$TIME_DIFF" >> "$VERIFY_DIR/css_file_stat.txt"
fi

# Copy reference screenshots to verification directory
echo "Copying reference screenshots..."
cp /tmp/screenshot_broken_initial.png "$VERIFY_DIR/" 2>/dev/null || echo "⚠ Initial broken screenshot not found"
cp /tmp/screenshot_correct_reference.png "$VERIFY_DIR/" 2>/dev/null || echo "⚠ Reference correct screenshot not found"

# Check browser cache directory size as rough indicator of cache clearing
echo "Checking cache state..."
CACHE_DIR="$CHROME_PROFILE/Cache"
if [ -d "$CACHE_DIR" ]; then
    CACHE_SIZE=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1)
    echo "cache_size_bytes=$CACHE_SIZE" > "$VERIFY_DIR/cache_info.txt"
else
    echo "cache_size_bytes=0" > "$VERIFY_DIR/cache_info.txt"
fi

# Copy all verification files to standard /tmp location
echo "Copying verification files..."
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# List what we captured
echo ""
echo "Captured verification files:"
ls -lh "$VERIFY_DIR"

echo "✅ Export complete"
echo "Verification files ready in: $VERIFY_DIR"