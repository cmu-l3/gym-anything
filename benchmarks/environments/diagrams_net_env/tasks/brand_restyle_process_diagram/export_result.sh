#!/bin/bash
echo "=== Exporting brand_restyle_process_diagram result ==="

# 1. Capture final screenshot (CRITICAL evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DRAWIO_FILE="/home/ga/Diagrams/customer_onboarding.drawio"
PNG_FILE="/home/ga/Diagrams/exports/customer_onboarding.png"
PDF_FILE="/home/ga/Diagrams/exports/customer_onboarding.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check files
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE=0

if [ -f "$DRAWIO_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$DRAWIO_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$DRAWIO_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

PNG_EXISTS="false"
if [ -f "$PNG_FILE" ]; then PNG_EXISTS="true"; fi

PDF_EXISTS="false"
if [ -f "$PDF_FILE" ]; then PDF_EXISTS="true"; fi

# 4. Create result JSON (using temp file)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "png_exists": $PNG_EXISTS,
    "pdf_exists": $PDF_EXISTS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 5. Move JSON to final location and set permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# 6. Copy the .drawio file to temp for verifier to access easily
if [ -f "$DRAWIO_FILE" ]; then
    cp "$DRAWIO_FILE" /tmp/final_diagram.drawio
    chmod 666 /tmp/final_diagram.drawio
fi

echo "=== Export complete ==="