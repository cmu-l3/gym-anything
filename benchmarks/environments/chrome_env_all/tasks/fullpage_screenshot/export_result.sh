#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Full-Page Screenshot Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq python3 || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create verification directory
VERIFY_DIR="/tmp/screenshot_verification"
mkdir -p "$VERIFY_DIR"

# Look for screenshots in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
echo "Searching for screenshot files in Downloads folder..."

# Find PNG files created in the last 5 minutes
echo "Listing recent PNG files:"
find "$DOWNLOADS_DIR" -name "*.png" -type f -mmin -5 2>/dev/null || true

# Copy any recent PNG files to verification directory
RECENT_SCREENSHOTS=$(find "$DOWNLOADS_DIR" -name "*.png" -type f -mmin -5 2>/dev/null || true)

if [ -n "$RECENT_SCREENSHOTS" ]; then
    echo "✓ Found screenshot file(s):"
    echo "$RECENT_SCREENSHOTS"
    
    # Copy all recent screenshots to verification directory
    while IFS= read -r screenshot_file; do
        if [ -f "$screenshot_file" ]; then
            filename=$(basename "$screenshot_file")
            cp "$screenshot_file" "$VERIFY_DIR/"
            echo "  Copied: $filename"
            
            # Get file info
            ls -lh "$screenshot_file"
        fi
    done <<< "$RECENT_SCREENSHOTS"
    
    # Create a list of screenshot filenames for the verifier
    find "$VERIFY_DIR" -name "*.png" -type f -printf "%f\n" > "$VERIFY_DIR/screenshot_list.txt"
    echo "✓ Screenshot list saved to verification directory"
else
    echo "⚠ No recent PNG files found in Downloads folder"
    touch "$VERIFY_DIR/screenshot_list.txt"
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Check if DevTools was opened (look for devtools:// tabs)
DEVTOOLS_OPEN=$(curl -s http://localhost:9222/json 2>/dev/null | jq '[.[] | select(.url | contains("devtools://"))] | length')
if [ "$DEVTOOLS_OPEN" -gt 0 ]; then
    echo "✓ DevTools appears to have been opened"
    echo "true" > "$VERIFY_DIR/devtools_opened.txt"
else
    echo "⚠ DevTools may not have been opened"
    echo "false" > "$VERIFY_DIR/devtools_opened.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Desktop screenshot saved for debugging"
fi

# List Downloads folder contents for debugging
echo "Current Downloads folder contents:"
ls -lah "$DOWNLOADS_DIR" || true

# Copy verification info to standard temp location
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files available in: $VERIFY_DIR"