#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print Settings Configuration Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure any pending operations complete
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 2

# Wait a bit to ensure any PDF generation completes
echo "Waiting for PDF generation to complete..."
sleep 3

# Create temporary verification directory
VERIFY_DIR="/tmp/print_settings_verification"
mkdir -p "$VERIFY_DIR"

# Look for the PDF in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
TARGET_PDF="webpage_print_landscape.pdf"

echo "Searching for PDF in Downloads folder..."

# First, try the exact expected filename
if [ -f "$DOWNLOADS_DIR/$TARGET_PDF" ]; then
    echo "✓ Found expected PDF: $TARGET_PDF"
    cp "$DOWNLOADS_DIR/$TARGET_PDF" "$VERIFY_DIR/"
    echo "$TARGET_PDF" > "$VERIFY_DIR/pdf_filename.txt"
    ls -lh "$DOWNLOADS_DIR/$TARGET_PDF"
else
    echo "Expected PDF not found by exact name, searching for landscape-related PDFs..."
    
    # Find any PDF with "landscape" in the name created in the last 10 minutes
    LANDSCAPE_PDF=$(find "$DOWNLOADS_DIR" -name "*landscape*.pdf" -type f -mmin -10 -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    
    if [ -n "$LANDSCAPE_PDF" ] && [ -f "$LANDSCAPE_PDF" ]; then
        PDF_NAME=$(basename "$LANDSCAPE_PDF")
        echo "✓ Found landscape PDF: $PDF_NAME"
        cp "$LANDSCAPE_PDF" "$VERIFY_DIR/"
        echo "$PDF_NAME" > "$VERIFY_DIR/pdf_filename.txt"
        ls -lh "$LANDSCAPE_PDF"
    else
        echo "No landscape PDF found, searching for any recent PDF..."
        
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
            ls -lah "$DOWNLOADS_DIR" 2>/dev/null || true
        fi
    fi
fi

# Record timestamp for verification
date +%s > "$VERIFY_DIR/export_timestamp.txt"

# Capture active tab URL via CDP for additional context
echo "Capturing active tab URL via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL"
    echo "$ACTIVE_URL" > "$VERIFY_DIR/final_url.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Copy verification info to standard temp location for verifier access
cp -r "$VERIFY_DIR"/* /tmp/ 2>/dev/null || true

# List all PDFs in Downloads with timestamps for debugging
echo ""
echo "All PDF files in Downloads folder:"
find "$DOWNLOADS_DIR" -name "*.pdf" -type f -printf "%T+ %p\n" 2>/dev/null | sort -r || true

echo ""
echo "✅ Export complete"
echo "Verification files copied to: $VERIFY_DIR"