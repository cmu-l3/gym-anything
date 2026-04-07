#!/bin/bash
# Export script for extract_chart_summary

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/patient_summary.txt"

# 1. Check Output File
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Prepare verification data
# Copy Ground Truth (which was hidden) to a temp location readable by the export process
# but packaged into the result or kept separate.
# We will copy it to a standard path that the verifier knows how to retrieve via copy_from_env.
cp /tmp/ground_truth.json /tmp/verification_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/verification_ground_truth.json

# Copy agent output to temp location for consistency
cp "$OUTPUT_FILE" /tmp/verification_output.txt 2>/dev/null || true
chmod 644 /tmp/verification_output.txt

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "output_path": "/tmp/verification_output.txt",
    "ground_truth_path": "/tmp/verification_ground_truth.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"