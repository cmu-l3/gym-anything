#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Multiple File Downloads Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window one last time
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/download_verification"
mkdir -p "$VERIFY_DIR"

# Capture current time for verification
date +%s > "$VERIFY_DIR/export_time.txt"

# List Downloads folder contents
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Listing Downloads folder contents..."
ls -lah "$DOWNLOADS_DIR" > "$VERIFY_DIR/downloads_listing.txt" 2>&1 || true
cat "$VERIFY_DIR/downloads_listing.txt"

# Check for expected files
echo "Checking for downloaded files..."
for filename in "sample.pdf" "image.png" "document.txt"; do
    if [ -f "$DOWNLOADS_DIR/$filename" ]; then
        echo "✓ Found: $filename ($(stat -c%s "$DOWNLOADS_DIR/$filename") bytes)"
        # Copy file info for verification
        stat "$DOWNLOADS_DIR/$filename" > "$VERIFY_DIR/${filename}.stat" 2>&1 || true
    else
        echo "✗ Missing: $filename"
    fi
done

# Check for partial downloads (.crdownload files)
PARTIAL_COUNT=$(find "$DOWNLOADS_DIR" -name "*.crdownload" 2>/dev/null | wc -l)
if [ "$PARTIAL_COUNT" -gt 0 ]; then
    echo "⚠ Warning: Found $PARTIAL_COUNT partial download(s)"
    find "$DOWNLOADS_DIR" -name "*.crdownload" -ls || true
fi

# Capture Chrome downloads page state (if accessible)
echo "Checking Chrome downloads via CDP..."
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

# Copy task start time if available
if [ -f /tmp/task_start_time.txt ]; then
    cp /tmp/task_start_time.txt "$VERIFY_DIR/" || true
fi

echo "✅ Export complete"
echo "Verification files saved to: $VERIFY_DIR"