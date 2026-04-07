#!/bin/bash
# Export script for export_routine_logbook task

echo "=== Exporting export_routine_logbook result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_FILE="/home/ga/Downloads/Push-Pull-Legs-Logbook.pdf"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
CREATED_DURING_TASK="false"
PDF_CONTAINS_TEXT_FALLBACK="false"

# Check if the expected file exists
if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Simple fallback text extraction in case pdfminer fails in verifier.py
    if strings "$EXPECTED_FILE" | grep -qi "Push-Pull-Legs"; then
        PDF_CONTAINS_TEXT_FALLBACK="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "pdf_contains_text_fallback": $PDF_CONTAINS_TEXT_FALLBACK,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location handling permissions
rm -f /tmp/export_routine_logbook_result.json 2>/dev/null || sudo rm -f /tmp/export_routine_logbook_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/export_routine_logbook_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/export_routine_logbook_result.json
chmod 666 /tmp/export_routine_logbook_result.json 2>/dev/null || sudo chmod 666 /tmp/export_routine_logbook_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/export_routine_logbook_result.json"
cat /tmp/export_routine_logbook_result.json

echo "=== Export Complete ==="