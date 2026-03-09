#!/bin/bash
echo "=== Exporting document_menu_inventory results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/menu_inventory_report.txt"
GROUND_TRUTH="/tmp/ground_truth_menu.txt"

# Check if output file exists
if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare files for export (copy to /tmp with known names for verifier)
if [ -f "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" /tmp/agent_report.txt
    chmod 666 /tmp/agent_report.txt
fi

if [ -f "$GROUND_TRUTH" ]; then
    cp "$GROUND_TRUTH" /tmp/ground_truth_export.txt
    chmod 666 /tmp/ground_truth_export.txt
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "report_path": "/tmp/agent_report.txt",
    "ground_truth_path": "/tmp/ground_truth_export.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="