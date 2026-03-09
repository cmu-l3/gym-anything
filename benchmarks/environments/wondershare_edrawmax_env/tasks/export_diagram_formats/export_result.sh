#!/bin/bash
echo "=== Exporting export_diagram_formats task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPORTS_DIR="/home/ga/Documents/exports"
PDF_FILE="${EXPORTS_DIR}/diagram_export.pdf"
PNG_FILE="${EXPORTS_DIR}/diagram_export.png"

# --- PDF STATUS ---
if [ -f "$PDF_FILE" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c %s "$PDF_FILE" 2>/dev/null || echo "0")
    PDF_MTIME=$(stat -c %Y "$PDF_FILE" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -ge "$TASK_START" ]; then
        PDF_FRESH="true"
    else
        PDF_FRESH="false"
    fi
else
    # Check for alternate names
    ALT_PDF=$(find "$EXPORTS_DIR" -maxdepth 1 -name "*.pdf" -type f -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$ALT_PDF" ]; then
        PDF_EXISTS="true"
        PDF_FILE="$ALT_PDF" # Update for JSON
        PDF_SIZE=$(stat -c %s "$ALT_PDF" 2>/dev/null || echo "0")
        PDF_MTIME=$(stat -c %Y "$ALT_PDF" 2>/dev/null || echo "0")
        PDF_FRESH="true"
    else
        PDF_EXISTS="false"
        PDF_SIZE="0"
        PDF_MTIME="0"
        PDF_FRESH="false"
    fi
fi

# --- PNG STATUS ---
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_FILE" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_FILE" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -ge "$TASK_START" ]; then
        PNG_FRESH="true"
    else
        PNG_FRESH="false"
    fi
else
    # Check for alternate names
    ALT_PNG=$(find "$EXPORTS_DIR" -maxdepth 1 -name "*.png" -type f -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$ALT_PNG" ]; then
        PNG_EXISTS="true"
        PNG_FILE="$ALT_PNG" # Update for JSON
        PNG_SIZE=$(stat -c %s "$ALT_PNG" 2>/dev/null || echo "0")
        PNG_MTIME=$(stat -c %Y "$ALT_PNG" 2>/dev/null || echo "0")
        PNG_FRESH="true"
    else
        PNG_EXISTS="false"
        PNG_SIZE="0"
        PNG_MTIME="0"
        PNG_FRESH="false"
    fi
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_exists": $PDF_EXISTS,
    "pdf_path": "$PDF_FILE",
    "pdf_size": $PDF_SIZE,
    "pdf_fresh": $PDF_FRESH,
    "png_exists": $PNG_EXISTS,
    "png_path": "$PNG_FILE",
    "png_size": $PNG_SIZE,
    "png_fresh": $PNG_FRESH,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="