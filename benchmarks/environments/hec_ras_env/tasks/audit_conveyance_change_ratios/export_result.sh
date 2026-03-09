#!/bin/bash
echo "=== Exporting Conveyance Audit Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/hec_ras_results/conveyance_audit.csv"
GROUND_TRUTH_PATH="/var/lib/hec-ras/ground_truth_conveyance.csv"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Look for Python scripts created by agent (evidence of work)
SCRIPT_COUNT=$(find /home/ga/Documents -name "*.py" -newermt "@$TASK_START" 2>/dev/null | wc -l)

# 4. Prepare files for verification
# We need to copy the hidden ground truth and the agent's output to a temp location
# so the host verifier can read them via copy_from_env
cp "$GROUND_TRUTH_PATH" /tmp/ground_truth.csv 2>/dev/null || true
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/agent_output.csv 2>/dev/null || true
fi
chmod 644 /tmp/ground_truth.csv /tmp/agent_output.csv 2>/dev/null || true

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "script_count": $SCRIPT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"