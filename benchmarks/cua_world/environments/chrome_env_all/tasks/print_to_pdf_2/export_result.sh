#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print to PDF Task Export: print_to_pdf@1 ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Wait a moment for any PDF save operations to complete
sleep 2

# Check if PDF exists in Downloads
PDF_PATH="/home/ga/Downloads/webpage_archive.pdf"
if [ -f "$PDF_PATH" ]; then
    echo "✓ PDF file found at $PDF_PATH"
    PDF_SIZE=$(stat -c%s "$PDF_PATH" 2>/dev/null || stat -f%z "$PDF_PATH" 2>/dev/null || echo "0")
    echo "  PDF size: $PDF_SIZE bytes"
    
    # Copy PDF to /tmp for verification
    cp "$PDF_PATH" /tmp/webpage_archive.pdf
    chmod 644 /tmp/webpage_archive.pdf
    echo "  PDF copied to /tmp for verification"
else
    echo "⚠ Warning: PDF file not found at $PDF_PATH"
    # List Downloads directory for debugging
    echo "Contents of Downloads directory:"
    ls -lah /home/ga/Downloads/ 2>/dev/null || echo "  Could not list Downloads directory"
    
    # Check for PDF with similar names (in case of typo)
    find /home/ga/Downloads/ -name "*.pdf" -type f 2>/dev/null | head -5 || true
fi

# Copy the original test page for verification comparison
cp /tmp/test_page.html /tmp/original_test_page.html 2>/dev/null || true

# Capture active tab info via CDP for additional context
echo "Capturing Chrome state via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json 2>/dev/null || echo "")
    echo "Active URL: $ACTIVE_URL"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved to /tmp/final_screenshot.png"
fi

echo "✅ Export complete"