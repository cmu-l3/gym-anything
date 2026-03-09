#!/bin/bash
echo "=== Exporting identify_hydraulic_bottleneck results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file details
OUTPUT_PATH="/home/ga/Documents/hec_ras_results/bottleneck_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_CONTENT=""
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (limit size just in case)
    OUTPUT_CONTENT=$(head -c 2048 "$OUTPUT_PATH" | base64 -w 0)
fi

# 3. Check for ground truth availability
GT_EXISTS="false"
if [ -f "/tmp/ground_truth.json" ]; then
    GT_EXISTS="true"
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_content_b64": "$OUTPUT_CONTENT",
    "ground_truth_exists": $GT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save files for verifier to pick up
# We save the result json
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# We also make sure the ground truth file is accessible
if [ -f "/tmp/ground_truth.json" ]; then
    chmod 666 /tmp/ground_truth.json 2>/dev/null || true
fi

rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="