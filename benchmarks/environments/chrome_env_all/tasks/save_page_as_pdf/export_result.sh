#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save Page as PDF Task Export ==="

# Install utilities if not present
# apt-get update -qq && apt-get install -y -qq curl jq || true

# Focus Chrome window to ensure it's in the foreground
wid=$(wmctrl -l | grep -i 'Google Chrome' | awk '{print $1; exit}')
if [ -n "$wid" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -ia $wid" || true
fi
sleep 1

# Create temporary verification directory
VERIFY_DIR="/tmp/pdf_save_verification"
mkdir -p "$VERIFY_DIR"

# Look for PDF files in Downloads folder
DOWNLOADS_DIR="/home/ga/Downloads"
TARGET_KEYWORDS="support chat transcript cs-2024"

echo "Searching for PDF files in Downloads folder..."
echo "Downloads directory: $DOWNLOADS_DIR"

# Find all PDF files in Downloads (created in last 10 minutes)
RECENT_PDFS=$(find "$DOWNLOADS_DIR" -name "*.pdf" -type f -mmin -10 2>/dev/null || true)

if [ -z "$RECENT_PDFS" ]; then
    echo "⚠ No recent PDF files found in Downloads folder"
    echo "none" > "$VERIFY_DIR/found_pdf.txt"
else
    # Count PDFs found
    PDF_COUNT=$(echo "$RECENT_PDFS" | wc -l)
    echo "✓ Found $PDF_COUNT recent PDF file(s)"
    
    # Get the most recent PDF
    MOST_RECENT=$(echo "$RECENT_PDFS" | head -1)
    PDF_NAME=$(basename "$MOST_RECENT")
    PDF_SIZE=$(stat -f%z "$MOST_RECENT" 2>/dev/null || stat -c%s "$MOST_RECENT" 2>/dev/null || echo "0")
    
    echo "Most recent PDF: $PDF_NAME (${PDF_SIZE} bytes)"
    
    # Copy PDF to verification directory
    cp "$MOST_RECENT" "$VERIFY_DIR/" || true
    
    # Save PDF metadata
    echo "$PDF_NAME" > "$VERIFY_DIR/found_pdf.txt"
    echo "$PDF_SIZE" > "$VERIFY_DIR/pdf_size.txt"
    ls -lh "$MOST_RECENT" > "$VERIFY_DIR/pdf_details.txt"
    
    # If multiple PDFs found, list them all
    if [ "$PDF_COUNT" -gt 1 ]; then
        echo "Additional PDFs found:" >> "$VERIFY_DIR/all_pdfs.txt"
        echo "$RECENT_PDFS" >> "$VERIFY_DIR/all_pdfs.txt"
    fi
fi

# List all files in Downloads for debugging
echo "Full contents of Downloads folder:" > "$VERIFY_DIR/downloads_listing.txt"
ls -lah "$DOWNLOADS_DIR" >> "$VERIFY_DIR/downloads_listing.txt" 2>&1 || true

# Capture active tab URL via CDP for additional context
echo "Capturing active tab information via CDP..."
if curl -s http://localhost:9222/json > /tmp/chrome_tabs.json 2>/dev/null; then
    ACTIVE_URL=$(jq -r '[.[] | select(.type == "page")][0].url // ""' /tmp/chrome_tabs.json)
    ACTIVE_TITLE=$(jq -r '[.[] | select(.type == "page")][0].title // ""' /tmp/chrome_tabs.json)
    echo "Active URL: $ACTIVE_URL" | tee "$VERIFY_DIR/final_url.txt"
    echo "Active Title: $ACTIVE_TITLE" | tee "$VERIFY_DIR/final_title.txt"
fi

# Take a final screenshot for debugging
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root $VERIFY_DIR/final_screenshot.png" 2>/dev/null || true
    echo "Screenshot saved"
fi

# Record task completion timestamp
date '+%Y-%m-%d %H:%M:%S' > "$VERIFY_DIR/completion_time.txt"

echo "✅ Export complete"
echo "Verification files prepared in: $VERIFY_DIR"

# List verification files created
echo "Files available for verification:"
ls -lh "$VERIFY_DIR/" || true