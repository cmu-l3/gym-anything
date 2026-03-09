#!/bin/bash
echo "=== Exporting Generate Traceability Report Result ==="

source /workspace/scripts/task_utils.sh

# 1. Record end time and screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# 2. Find the most recently created PDF in Downloads
# We look for files created after TASK_START
DOWNLOAD_DIR="/home/ga/Downloads"
LATEST_PDF=$(find "$DOWNLOAD_DIR" -name "*.pdf" -type f -newermt "@$TASK_START" -printf "%T@ %p\n" | sort -n | tail -1 | awk '{print $2}')

PDF_FOUND="false"
PDF_PATH=""
PDF_SIZE="0"
PDF_FILENAME=""

if [ -n "$LATEST_PDF" ] && [ -f "$LATEST_PDF" ]; then
    PDF_FOUND="true"
    PDF_PATH="$LATEST_PDF"
    PDF_SIZE=$(stat -c %s "$LATEST_PDF")
    PDF_FILENAME=$(basename "$LATEST_PDF")
    echo "Found new PDF: $PDF_FILENAME ($PDF_SIZE bytes)"
else
    echo "No new PDF found in $DOWNLOAD_DIR"
fi

# 3. Create JSON result
# We will copy the PDF out in the verifier, so we just pass the path here.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_found": $PDF_FOUND,
    "pdf_path": "$PDF_PATH",
    "pdf_filename": "$PDF_FILENAME",
    "pdf_size_bytes": $PDF_SIZE,
    "download_dir": "$DOWNLOAD_DIR"
}
EOF

# 4. Save result JSON
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# 5. If PDF exists, copy it to a temporary location with a known name for easier extraction by verifier
if [ "$PDF_FOUND" == "true" ]; then
    cp "$PDF_PATH" /tmp/report_artifact.pdf
    chmod 666 /tmp/report_artifact.pdf
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="