#!/bin/bash
echo "=== Exporting investigation report results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/nightshade_report.json"
GROUND_TRUTH_PATH="/root/validation/ground_truth.json"

# Check output file status
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
    
    # Copy agent output to temp for verification (readable by verifier)
    cp "$OUTPUT_PATH" /tmp/agent_output.json
    chmod 644 /tmp/agent_output.json
fi

# Copy ground truth to temp for verification
if [ -f "$GROUND_TRUTH_PATH" ]; then
    cp "$GROUND_TRUTH_PATH" /tmp/ground_truth.json
    chmod 644 /tmp/ground_truth.json
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result manifest
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "ground_truth_available": $([ -f "/tmp/ground_truth.json" ] && echo "true" || echo "false")
}
EOF

# Move manifest to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"