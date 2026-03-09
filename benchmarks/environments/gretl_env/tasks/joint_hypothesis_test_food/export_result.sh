#!/bin/bash
echo "=== Exporting Joint Hypothesis Test Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Get task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check output file
OUTPUT_PATH="/home/ga/Documents/gretl_output/joint_test_results.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check if Gretl was running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 5. Prepare ground truth for export (copy to temp so verifier can access it via copy_from_env)
# The verifier will need to compare the user's file against this one.
cp /var/lib/gretl/ground_truth_test.txt /tmp/ground_truth_ref.txt 2>/dev/null || echo "Error: Ground truth missing" > /tmp/ground_truth_ref.txt
chmod 644 /tmp/ground_truth_ref.txt

# 6. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "output_file_path": "$OUTPUT_PATH",
    "ground_truth_path": "/tmp/ground_truth_ref.txt"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="