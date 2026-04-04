#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save Webpage Complete Task Export: save_page_complete@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Capture active tab URL via CDP for verification
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs_final.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs_final.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs_final.json)
    echo "Active URL: $ACTIVE_URL"
    echo "Active title: $ACTIVE_TITLE"
    echo "$ACTIVE_URL" > /tmp/final_url.txt
    echo "$ACTIVE_TITLE" > /tmp/final_title.txt
fi

# Check if files were created in Downloads
DOWNLOADS_DIR="/home/ga/Downloads"
echo ""
echo "Checking Downloads folder for saved files..."
echo "Looking for:"
echo "  - web_archiving_complete.html"
echo "  - web_archiving_complete_files/ (directory)"
echo ""

# Create verification info file
VERIFY_FILE="/tmp/save_complete_verification.txt"
echo "=== Save Webpage Complete Verification Info ===" > "$VERIFY_FILE"
echo "Timestamp: $(date)" >> "$VERIFY_FILE"
echo "" >> "$VERIFY_FILE"

# Check HTML file
if [ -f "$DOWNLOADS_DIR/web_archiving_complete.html" ]; then
    FILE_SIZE=$(stat -f%z "$DOWNLOADS_DIR/web_archiving_complete.html" 2>/dev/null || stat -c%s "$DOWNLOADS_DIR/web_archiving_complete.html" 2>/dev/null || echo "0")
    echo "✓ HTML file found: web_archiving_complete.html ($FILE_SIZE bytes)" | tee -a "$VERIFY_FILE"
else
    echo "✗ HTML file NOT found: web_archiving_complete.html" | tee -a "$VERIFY_FILE"
fi

# Check resources folder
if [ -d "$DOWNLOADS_DIR/web_archiving_complete_files" ]; then
    FILE_COUNT=$(find "$DOWNLOADS_DIR/web_archiving_complete_files" -type f 2>/dev/null | wc -l)
    FOLDER_SIZE=$(du -sh "$DOWNLOADS_DIR/web_archiving_complete_files" 2>/dev/null | cut -f1)
    echo "✓ Resources folder found: web_archiving_complete_files/ ($FILE_COUNT files, $FOLDER_SIZE)" | tee -a "$VERIFY_FILE"
    
    # Count file types
    CSS_COUNT=$(find "$DOWNLOADS_DIR/web_archiving_complete_files" -type f -name "*.css" 2>/dev/null | wc -l)
    IMG_COUNT=$(find "$DOWNLOADS_DIR/web_archiving_complete_files" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.svg" -o -name "*.gif" \) 2>/dev/null | wc -l)
    JS_COUNT=$(find "$DOWNLOADS_DIR/web_archiving_complete_files" -type f -name "*.js" 2>/dev/null | wc -l)
    
    echo "  - CSS files: $CSS_COUNT" | tee -a "$VERIFY_FILE"
    echo "  - Image files: $IMG_COUNT" | tee -a "$VERIFY_FILE"
    echo "  - JavaScript files: $JS_COUNT" | tee -a "$VERIFY_FILE"
else
    echo "✗ Resources folder NOT found: web_archiving_complete_files/" | tee -a "$VERIFY_FILE"
fi

# List all files in Downloads for debugging
echo "" >> "$VERIFY_FILE"
echo "All files in Downloads folder:" >> "$VERIFY_FILE"
ls -lah "$DOWNLOADS_DIR" 2>/dev/null >> "$VERIFY_FILE" || echo "Could not list Downloads" >> "$VERIFY_FILE"

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot_save_complete.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot_save_complete.png"
fi

echo ""
echo "✅ Export complete"
echo "Verification info saved to: $VERIFY_FILE"