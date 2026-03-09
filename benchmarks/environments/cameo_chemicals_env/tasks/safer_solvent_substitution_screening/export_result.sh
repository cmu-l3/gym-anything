#!/bin/bash
# export_result.sh - Post-task hook for safer_solvent_substitution_screening

echo "=== Exporting Solvent Screening Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final State Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Output File Status
OUTPUT_PATH="/home/ga/Documents/solvent_screening_matrix.txt"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Verify file was modified AFTER task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Make a copy for extraction
    cp "$OUTPUT_PATH" /tmp/exported_matrix.txt
    chmod 666 /tmp/exported_matrix.txt
fi

# 3. Create Result JSON
# We include metadata about the file and execution
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "output_file_path": "/tmp/exported_matrix.txt"
}
EOF

# 4. Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="