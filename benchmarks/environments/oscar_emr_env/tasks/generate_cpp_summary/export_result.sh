#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOWNLOAD_DIR="/home/ga/Downloads"

# Find the most recently created PDF in downloads
LATEST_PDF=$(find "$DOWNLOAD_DIR" -name "*.pdf" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")

PDF_FOUND="false"
PDF_PATH=""
PDF_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -n "$LATEST_PDF" ] && [ -f "$LATEST_PDF" ]; then
    PDF_FOUND="true"
    PDF_PATH="$LATEST_PDF"
    PDF_SIZE=$(stat -c %s "$LATEST_PDF" 2>/dev/null || echo "0")
    
    # Check modification time
    PDF_MTIME=$(stat -c %Y "$LATEST_PDF" 2>/dev/null || echo "0")
    if [ "$PDF_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy to a standard location for easy retrieval by verifier
    cp "$LATEST_PDF" /tmp/cpp_output.pdf
    chmod 666 /tmp/cpp_output.pdf
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pdf_found": $PDF_FOUND,
    "pdf_path": "$PDF_PATH",
    "pdf_size_bytes": $PDF_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="