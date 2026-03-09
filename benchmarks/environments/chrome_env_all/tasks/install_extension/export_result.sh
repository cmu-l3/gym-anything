#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Extension Installation Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
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

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

# IMPORTANT: Close Chrome gracefully to ensure extensions are persisted to disk
# Chrome extensions are fully written to disk when browser closes
echo "Closing Chrome to save extension data..."
pkill -f "google-chrome" || true
sleep 3

# Double-check Chrome is closed
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Force killing Chrome..."
    pkill -9 -f "google-chrome" || true
    sleep 1
fi

# Determine Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

EXTENSIONS_DIR="$CHROME_PROFILE/Extensions"

# Record final extension state
echo "Recording final extension state..."
FINAL_FILE="/tmp/final_extensions.txt"
if [ -d "$EXTENSIONS_DIR" ]; then
    ls -1 "$EXTENSIONS_DIR" 2>/dev/null | sort > "$FINAL_FILE" || touch "$FINAL_FILE"
    FINAL_COUNT=$(wc -l < "$FINAL_FILE" 2>/dev/null || echo "0")
    echo "✓ Final: $FINAL_COUNT extension(s) installed"
    
    # List extension names for debugging
    echo "Extension IDs found:"
    cat "$FINAL_FILE" || true
else
    touch "$FINAL_FILE"
    echo "⚠ Warning: Extensions directory not found at $EXTENSIONS_DIR"
fi

# Find all manifest.json files
if [ -d "$EXTENSIONS_DIR" ]; then
    find "$EXTENSIONS_DIR" -name "manifest.json" -type f > /tmp/final_manifests.txt 2>/dev/null || touch /tmp/final_manifests.txt
    MANIFEST_COUNT=$(wc -l < /tmp/final_manifests.txt 2>/dev/null || echo "0")
    echo "✓ Found $MANIFEST_COUNT manifest file(s)"
fi

# Compare baseline and final
if [ -f /tmp/baseline_extensions.txt ] && [ -f "$FINAL_FILE" ]; then
    BASELINE_COUNT=$(wc -l < /tmp/baseline_extensions.txt 2>/dev/null || echo "0")
    DIFF_COUNT=$((FINAL_COUNT - BASELINE_COUNT))
    
    if [ $DIFF_COUNT -gt 0 ]; then
        echo "✓ $DIFF_COUNT new extension(s) detected"
        comm -13 /tmp/baseline_extensions.txt "$FINAL_FILE" > /tmp/new_extensions.txt
        echo "New extension IDs:"
        cat /tmp/new_extensions.txt || true
    elif [ $DIFF_COUNT -eq 0 ]; then
        echo "⚠ No new extensions detected"
    else
        echo "⚠ Warning: Extension count decreased by $((DIFF_COUNT * -1))"
    fi
fi

# Save Chrome profile path for verifier
echo "$CHROME_PROFILE" > /tmp/chrome_profile_path.txt

echo "✅ Export complete"
echo "Extension data ready for verification"