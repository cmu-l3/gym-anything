#!/bin/bash
# set -euo pipefail

echo "=== Exporting Annual Report Result ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/annual_report_start_ts 2>/dev/null || echo "0")

# Focus WPS window and take final screenshot
wid=$(get_wps_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi
take_screenshot /tmp/annual_report_final.png

# Check for the output document in expected locations
OUTPUT_DOC=""
DOC_EXISTS="false"
DOC_SIZE="0"
DOC_CREATED_DURING_TASK="false"

for location in \
    "/home/ga/Documents/novabio_annual_report_final.docx" \
    "/home/ga/Documents/novabio_annual_report.docx" \
    "/home/ga/novabio_annual_report_final.docx" \
    "/home/ga/Documents/annual_report_final.docx"; do
    if [ -f "$location" ]; then
        OUTPUT_DOC="$location"
        echo "Found saved file at: $OUTPUT_DOC"
        break
    fi
done

if [ -n "$OUTPUT_DOC" ]; then
    DOC_EXISTS="true"
    DOC_SIZE=$(stat -c %s "$OUTPUT_DOC" 2>/dev/null || echo "0")
    DOC_MTIME=$(stat -c %Y "$OUTPUT_DOC" 2>/dev/null || echo "0")

    if [ "$DOC_MTIME" -gt "$TASK_START" ]; then
        DOC_CREATED_DURING_TASK="true"
    fi

    # Copy to tmp for verifier
    cp "$OUTPUT_DOC" /tmp/annual_report_output.docx 2>/dev/null || true
    chmod 666 /tmp/annual_report_output.docx 2>/dev/null || true
    echo "Document copied to /tmp/annual_report_output.docx"
else
    echo "Warning: Output document not found at any expected location"
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "document_exists": $DOC_EXISTS,
    "document_path": "$OUTPUT_DOC",
    "document_size": $DOC_SIZE,
    "doc_created_during_task": $DOC_CREATED_DURING_TASK,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "export_document": "/tmp/annual_report_output.docx",
    "screenshot": "/tmp/annual_report_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/annual_report_result.json 2>/dev/null || sudo rm -f /tmp/annual_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/annual_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/annual_report_result.json
chmod 666 /tmp/annual_report_result.json 2>/dev/null || sudo chmod 666 /tmp/annual_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/annual_report_result.json"
cat /tmp/annual_report_result.json

# Close WPS Writer
echo "Closing WPS Writer..."
safe_xdotool ga :1 key --delay 200 alt+F4
sleep 2

# Handle "Save changes?" dialog
safe_xdotool ga :1 key --delay 100 Tab
sleep 0.3
safe_xdotool ga :1 key --delay 100 Return
sleep 0.5

# Force kill if still running
if pgrep -f "wps" > /dev/null; then
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 1
fi

echo "=== Export Complete ==="
