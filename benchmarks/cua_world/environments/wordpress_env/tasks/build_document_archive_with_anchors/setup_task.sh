#!/bin/bash
# Setup script for build_document_archive_with_anchors task (pre_task hook)

echo "=== Setting up Document Archive task ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

# ============================================================
# Prepare Real Data (PDFs)
# ============================================================
ARCHIVE_DIR="/home/ga/Documents/Archive"
mkdir -p "$ARCHIVE_DIR"

# Base64 encoded minimal valid PDF (Fallback if curl fails)
TINY_PDF="JVBERi0xLjQKJcOkw7zDtsOfCjIgMCBvYmoKPDwvTGVuZ3RoIDMgMCBSPj4Kc3RyZWFtCkJUCjAvRjEgMjQgVGYKMTAwIDEwMCBUZAooU2FtcGxlIFBERiBEb2N1bWVudCkgVGoKRVQKZW5kc3RyZWFtCmVuZG9iagoxIDAgb2JqCjw8L1R5cGUvUGFnZS9QYXJlbnQgNCAwIFIvQ29udGVudHMgMiAwIFI+PgplbmRvYmoKNCAwIG9iago8PC9UeXBlL1BhZ2VzL0tpZHNbMSAwIFJdL0NvdW50IDE+PgplbmRvYmoKNSAwIG9iago8PC9UeXBlL0NhdGFsb2cvUGFnZXMgNCAwIFI+PgplbmRvYmoKNiAwIG9iago8PC9UeXBlL0ZvbnQvU3VidHlwZS9UeXBlMS9CYXNlRm9udC9IZWx2ZXRpY2E+PgplbmRvYmoKeHJlZgowIDcKMDAwMDAwMDAwMCA2NTM1MyBmIAowMDAwMDAwMTE1IDAwMDAwIG4gCjAwMDAwMDAwMTkgMDAwMDAgbiAKMDAwMDAwMDA5MiAwMDAwMCBuIAowMDAwMDAwMTY2IDAwMDAwIG4gCjAwMDAwMDAyMTcgMDAwMDAgbiAKMDAwMDAwMDI2NSAwMDAwMCBuIAp0cmFpbGVyCjw8L1NpemUgNy9Sb290IDUgMCBSPj4Kc3RhcnR4cmVmCjM1MwolJUVPRgo="

echo "Downloading archive PDFs from Wikipedia (Public Domain)..."
# Download Apollo 11
curl -s -L "https://en.wikipedia.org/api/rest_v1/page/pdf/Apollo_11" -o "$ARCHIVE_DIR/Apollo_11.pdf"
if [ ! -s "$ARCHIVE_DIR/Apollo_11.pdf" ]; then echo "$TINY_PDF" | base64 -d > "$ARCHIVE_DIR/Apollo_11.pdf"; fi

# Download James Webb Space Telescope
curl -s -L "https://en.wikipedia.org/api/rest_v1/page/pdf/James_Webb_Space_Telescope" -o "$ARCHIVE_DIR/James_Webb_Space_Telescope.pdf"
if [ ! -s "$ARCHIVE_DIR/James_Webb_Space_Telescope.pdf" ]; then echo "$TINY_PDF" | base64 -d > "$ARCHIVE_DIR/James_Webb_Space_Telescope.pdf"; fi

# Download Mars 2020
curl -s -L "https://en.wikipedia.org/api/rest_v1/page/pdf/Mars_2020" -o "$ARCHIVE_DIR/Mars_2020.pdf"
if [ ! -s "$ARCHIVE_DIR/Mars_2020.pdf" ]; then echo "$TINY_PDF" | base64 -d > "$ARCHIVE_DIR/Mars_2020.pdf"; fi

# Set ownership so the agent can access them
chown -R ga:ga "$ARCHIVE_DIR"
chmod -R 644 "$ARCHIVE_DIR"/*
chmod 755 "$ARCHIVE_DIR"

echo "PDFs prepared in $ARCHIVE_DIR:"
ls -lh "$ARCHIVE_DIR"

# ============================================================
# Clean up existing state & Record baselines
# ============================================================
cd /var/www/html/wordpress

# Delete any existing page with the target title
wp post list --post_type=page --title="Space Exploration Archive" --field=ID --allow-root | while read pid; do
    [ -n "$pid" ] && wp post delete "$pid" --force --allow-root 2>/dev/null
done

# Record baseline PDFs in the media library
echo "Recording baseline attachments..."
wp post list --post_type=attachment --post_mime_type=application/pdf --format=json --allow-root > /tmp/initial_pdfs.json
chmod 666 /tmp/initial_pdfs.json

# ============================================================
# Ensure Firefox is running
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/post-new.php?post_type=page' > /tmp/firefox.log 2>&1 &"
    sleep 8
fi

# Focus Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    echo "Firefox window focused: $WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="