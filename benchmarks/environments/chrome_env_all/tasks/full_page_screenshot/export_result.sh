#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Full-Page Screenshot Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Record task end time for verification
date +%s > /tmp/task_end_time.txt
echo "✓ Task end time recorded"

# Focus Chrome window to ensure proper state
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/screenshot_verification"
mkdir -p "$VERIFY_DIR"

# Look for screenshots in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for screenshots in Downloads folder..."

# Find PNG files, sorted by modification time (newest first)
SCREENSHOT_FILES=$(find "$DOWNLOADS_DIR" -name "*.png" -type f -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -5 | cut -d' ' -f2-)

if [ -z "$SCREENSHOT_FILES" ]; then
    echo "⚠ No PNG files found in Downloads"
    echo "none" > "$VERIFY_DIR/screenshot_found.txt"
else
    echo "✓ Found PNG file(s):"
    echo "$SCREENSHOT_FILES" | while read -r file; do
        if [ -f "$file" ]; then
            SIZE=$(stat -c%s "$file" 2>/dev/null || echo "0")
            SIZE_KB=$((SIZE / 1024))
            MTIME=$(stat -c%y "$file" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
            echo "  - $(basename "$file") (${SIZE_KB} KB, modified: $MTIME)"
        fi
    done
    
    # Save the most recent screenshot path
    MOST_RECENT=$(echo "$SCREENSHOT_FILES" | head -1)
    echo "$MOST_RECENT" > "$VERIFY_DIR/screenshot_path.txt"
    echo "yes" > "$VERIFY_DIR/screenshot_found.txt"
    
    # Copy screenshot to verification directory for easier access
    if [ -f "$MOST_RECENT" ]; then
        cp "$MOST_RECENT" "$VERIFY_DIR/captured_screenshot.png"
        echo "✓ Screenshot copied to verification directory"
    fi
fi

# List all Downloads contents for debugging
echo "Contents of Downloads folder:"
ls -lah "$DOWNLOADS_DIR" 2>/dev/null || echo "Could not list Downloads"

# Capture active tab URL via CDP for context
echo "Capturing active tab information..."
if curl -s http://localhost:9222/json > "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null; then
    ACTIVE_URL=$(jq -r '.[0].url // "unknown"' "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null || echo "unknown")
    ACTIVE_TITLE=$(jq -r '.[0].title // "unknown"' "$VERIFY_DIR/chrome_tabs.json" 2>/dev/null || echo "unknown")
    echo "Active URL: $ACTIVE_URL"
    echo "Active Title: $ACTIVE_TITLE"
fi

# Take a final screenshot of the desktop for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/desktop_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved for debugging"
fi

# Copy time tracking files
cp /tmp/task_start_time.txt "$VERIFY_DIR/" 2>/dev/null || echo "0" > "$VERIFY_DIR/task_start_time.txt"
cp /tmp/task_end_time.txt "$VERIFY_DIR/" 2>/dev/null || echo "9999999999" > "$VERIFY_DIR/task_end_time.txt"

echo "✅ Export complete"
echo "Verification files ready in: $VERIFY_DIR"