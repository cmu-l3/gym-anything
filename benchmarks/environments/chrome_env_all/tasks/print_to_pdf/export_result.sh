#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print-to-PDF Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/print_pdf_verification"
mkdir -p "$VERIFY_DIR"

# Look for the PDF in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
TARGET_PDF="machine_learning_fundamentals.pdf"

echo "Searching for PDF in Downloads folder..."

# First, try the exact expected filename
if [ -f "$DOWNLOADS_DIR/$TARGET_PDF" ]; then
    echo "✓ Found expected PDF: $TARGET_PDF"
    cp "$DOWNLOADS_DIR/$TARGET_PDF" "$VERIFY_DIR/"
    echo "$TARGET_PDF" > "$VERIFY_DIR/pdf_filename.txt"
    ls -lh "$DOWNLOADS_DIR/$TARGET_PDF"
else
    echo "Expected PDF not found by name, searching for recent PDFs..."
    
    # Find any PDF created in the last 10 minutes
    RECENT_PDF=$(find "$DOWNLOADS_DIR" -name "*.pdf" -type f -mmin -10 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$RECENT_PDF" ] && [ -f "$RECENT_PDF" ]; then
        PDF_NAME=$(basename "$RECENT_PDF")
        echo "✓ Found recent PDF: $PDF_NAME"
        cp "$RECENT_PDF" "$VERIFY_DIR/"
        echo "$PDF_NAME" > "$VERIFY_DIR/pdf_filename.txt"
        ls -lh "$RECENT_PDF"
    else
        echo "⚠ No PDF found in Downloads folder"
        echo "none" > "$VERIFY_DIR/pdf_filename.txt"
        
        # List all files in Downloads for debugging
        echo "Contents of Downloads folder:"
        ls -lah "$DOWNLOADS_DIR" || true
    fi
fi

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

echo "✅ Export complete"
echo "Verification files copied to: $VERIFY_DIR"