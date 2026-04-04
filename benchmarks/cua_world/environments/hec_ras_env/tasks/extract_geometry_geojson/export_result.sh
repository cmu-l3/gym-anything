#!/bin/bash
echo "=== Exporting extract_geometry_geojson results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/hec_ras_results/model_geometry.geojson"
INPUT_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.g04"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Copy files to /tmp for retrieval by verifier
# We copy BOTH the output and the input (to generate ground truth dynamically)
rm -f /tmp/agent_output.geojson /tmp/ground_truth_input.g04 2>/dev/null || true

if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" /tmp/agent_output.geojson
    chmod 644 /tmp/agent_output.geojson
fi

if [ -f "$INPUT_FILE" ]; then
    cp "$INPUT_FILE" /tmp/ground_truth_input.g04
    chmod 644 /tmp/ground_truth_input.g04
fi

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "output_path_in_container": "/tmp/agent_output.geojson",
    "input_path_in_container": "/tmp/ground_truth_input.g04"
}
EOF

# Move result json
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="