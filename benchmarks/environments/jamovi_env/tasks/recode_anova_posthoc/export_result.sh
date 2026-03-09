#!/bin/bash
echo "=== Exporting Recode & ANOVA Results ==="

# 1. Timestamps & Paths
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/Jamovi/ExamAnxietyRecoded.omv"

# 2. Check Output File Status
OUTPUT_EXISTS="false"
OUTPUT_MODIFIED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_MODIFIED_DURING_TASK="true"
    fi
fi

# 3. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Prepare Result JSON
# We bundle the ground truth calculated at setup time into the result
# so the verifier (on host) can access it.
GROUND_TRUTH_CONTENT=$(cat /tmp/ground_truth.json 2>/dev/null || echo "{}")

# Use a temp file for JSON construction to handle quoting correctly
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_modified_during_task": $OUTPUT_MODIFIED_DURING_TASK,
    "output_size": $OUTPUT_SIZE,
    "ground_truth": $GROUND_TRUTH_CONTENT
}
EOF

# 5. Save files for export
# Move the .omv file to /tmp/output.omv so verifier can copy it easily
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_FILE" /tmp/output.omv
    chmod 666 /tmp/output.omv
fi

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json