#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Device Mode Capture Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's active
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/device_mode_verification"
mkdir -p "$VERIFY_DIR"

# Export task start time for verifier
if [ -f /tmp/task_start_time.txt ]; then
    cp /tmp/task_start_time.txt "$VERIFY_DIR/"
    echo "✓ Task start time copied"
fi

# List all files in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Scanning Downloads folder for screenshots..."

if [ -d "$DOWNLOADS_DIR" ]; then
    # List all image files with details
    find "$DOWNLOADS_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -printf "%T@ %p\n" 2>/dev/null | sort -rn > "$VERIFY_DIR/downloads_list.txt" || true
    
    FILE_COUNT=$(cat "$VERIFY_DIR/downloads_list.txt" | wc -l)
    echo "✓ Found $FILE_COUNT image file(s) in Downloads"
    
    if [ "$FILE_COUNT" -gt 0 ]; then
        echo "Recent screenshots:"
        cat "$VERIFY_DIR/downloads_list.txt" | head -5 | while read -r line; do
            timestamp=$(echo "$line" | awk '{print $1}')
            filepath=$(echo "$line" | awk '{print $2}')
            filename=$(basename "$filepath")
            filesize=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null || echo "unknown")
            echo "  - $filename (${filesize} bytes, mtime: $timestamp)"
        done
    else
        echo "⚠ No image files found in Downloads folder"
    fi
else
    echo "⚠ Downloads folder not found"
    touch "$VERIFY_DIR/downloads_list.txt"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' "$VERIFY_DIR/chrome_tabs.json")
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' "$VERIFY_DIR/chrome_tabs.json")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
    echo "$ACTIVE_TITLE" > "$VERIFY_DIR/final_title.txt"
fi

# Take a final desktop screenshot for debugging (not for verification)
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/desktop_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved for debugging"
fi

# Copy Downloads folder content to verification directory
echo "Copying Downloads folder contents..."
cp -r "$DOWNLOADS_DIR" "$VERIFY_DIR/downloads_copy" 2>/dev/null || true

# Save current timestamp
date +%s > "$VERIFY_DIR/export_time.txt"

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"