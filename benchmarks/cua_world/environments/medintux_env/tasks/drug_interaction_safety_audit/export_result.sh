#!/bin/bash
echo "=== Exporting Drug Interaction Audit Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/interaction_alert_list.csv"
GT_PATH="/var/lib/medintux/ground_truth_interaction.csv"

# 1. Check Output Existence
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH")
    # Check if created during task
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 2. Check Database Connection (Anti-gaming: did they use SQL?)
# We can check .mysql_history if it exists, but it's not reliable if they use python or interactive mode without flush.
# Instead, we rely on the correctness of the result. Guessing Intersection of 2 sets of ~5 in 20 is statistically impossible.

# 3. Prepare Ground Truth for verifier (copy to tmp)
cp "$GT_PATH" /tmp/ground_truth.csv 2>/dev/null || true
chmod 644 /tmp/ground_truth.csv 2>/dev/null || true

# 4. Prepare Result for verifier
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" /tmp/agent_output.csv
    chmod 644 /tmp/agent_output.csv
fi

# 5. Take Screenshot
take_screenshot /tmp/task_final.png ga

# 6. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "output_size": $OUTPUT_SIZE,
    "ground_truth_available": $([ -f /tmp/ground_truth.csv ] && echo "true" || echo "false")
}
EOF

# Move Result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"