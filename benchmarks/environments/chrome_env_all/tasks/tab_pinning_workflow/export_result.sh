#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Tab Pinning Workflow Task Export: tab_pinning_workflow@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/tab_pinning_verification"
mkdir -p "$VERIFY_DIR"

# Capture all tabs via CDP
echo "Capturing tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_all_tabs.json" 2>/dev/null; then
    echo "✓ Successfully captured CDP tab information"
    
    # Filter to only page-type tabs
    jq '[.[] | select(.type == "page")]' "$VERIFY_DIR/chrome_all_tabs.json" > "$VERIFY_DIR/chrome_page_tabs.json"
    
    TAB_COUNT=$(jq 'length' "$VERIFY_DIR/chrome_page_tabs.json")
    echo "✓ Found $TAB_COUNT page tab(s)"
    
    # Extract URLs and titles for verification
    jq -r '.[] | "\(.url)|\(.title)"' "$VERIFY_DIR/chrome_page_tabs.json" > "$VERIFY_DIR/tab_list.txt"
    
    echo "Tab information:"
    cat "$VERIFY_DIR/tab_list.txt"
    
    # Export to standard /tmp location for verifier
    cp "$VERIFY_DIR/chrome_page_tabs.json" /tmp/chrome_page_tabs.json
    cp "$VERIFY_DIR/tab_list.txt" /tmp/tab_list.txt
else
    echo "⚠ Warning: Failed to capture CDP information"
    echo "[]" > "$VERIFY_DIR/chrome_page_tabs.json"
    echo "[]" > /tmp/chrome_page_tabs.json
    touch "$VERIFY_DIR/tab_list.txt"
    touch /tmp/tab_list.txt
fi

# Try to export Chrome session files which contain pinned state
echo "Attempting to export Chrome session files..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

if [ -f "$CHROME_PROFILE/Current Session" ]; then
    cp "$CHROME_PROFILE/Current Session" "$VERIFY_DIR/Current_Session" 2>/dev/null || true
    echo "✓ Copied Current Session file"
fi

if [ -f "$CHROME_PROFILE/Current Tabs" ]; then
    cp "$CHROME_PROFILE/Current Tabs" "$VERIFY_DIR/Current_Tabs" 2>/dev/null || true
    echo "✓ Copied Current Tabs file"
fi

# Alternative profile location
ALT_PROFILE="/home/ga/.config/google-chrome/Default"
if [ -f "$ALT_PROFILE/Current Session" ] && [ ! -f "$VERIFY_DIR/Current_Session" ]; then
    cp "$ALT_PROFILE/Current Session" "$VERIFY_DIR/Current_Session" 2>/dev/null || true
    echo "✓ Copied Current Session from alternative location"
fi

if [ -f "$ALT_PROFILE/Current Tabs" ] && [ ! -f "$VERIFY_DIR/Current_Tabs" ]; then
    cp "$ALT_PROFILE/Current Tabs" "$VERIFY_DIR/Current_Tabs" 2>/dev/null || true
    echo "✓ Copied Current Tabs from alternative location"
fi

# Copy verification files to /tmp for easier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    cp "$VERIFY_DIR/final_screenshot.png" /tmp/final_screenshot_pinning.png 2>/dev/null || true
    echo "Screenshot saved"
fi

# Log final tab count
FINAL_TAB_COUNT=$(jq 'length' "$VERIFY_DIR/chrome_page_tabs.json" 2>/dev/null || echo "0")
echo "Final tab count: $FINAL_TAB_COUNT"

echo "✅ Export complete"
echo "Verification files available at: $VERIFY_DIR"