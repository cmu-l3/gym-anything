#!/bin/bash
echo "=== Exporting Audit Result ==="

# Source task utils
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/audit_cataracte_2024.csv"
GROUND_TRUTH_PATH="/var/lib/medintux/ground_truth_audit.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check output file
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
CSV_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read CSV content (base64 to avoid JSON escaping issues)
    CSV_CONTENT=$(cat "$OUTPUT_PATH" | base64 -w 0)
fi

# Prepare verification data
# We copy the ground truth to the result JSON so the verifier (running on host) can see it
# In a real scenario, we might keep ground truth separate, but here we bundle for the python verifier

if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH_CONTENT=$(cat "$GROUND_TRUTH_PATH" | base64 -w 0)
else
    GROUND_TRUTH_CONTENT=""
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_content_b64": "$CSV_CONTENT",
    "ground_truth_b64": "$GROUND_TRUTH_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"