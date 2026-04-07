#!/bin/bash
echo "=== Exporting Practice Activity Volume Analysis Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/monthly_activity.csv"
GROUND_TRUTH_PATH="/var/lib/medintux/ground_truth_activity.csv"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Prepare result staging area
RESULT_DIR="/tmp/task_verification"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"

# Copy files for verifier
if [ "$OUTPUT_EXISTS" = "true" ]; then
    cp "$OUTPUT_PATH" "$RESULT_DIR/agent_output.csv"
fi
if [ -f "$GROUND_TRUTH_PATH" ]; then
    cp "$GROUND_TRUTH_PATH" "$RESULT_DIR/ground_truth.csv"
fi

# Create result JSON
cat > "$RESULT_DIR/result_metadata.json" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Bundle result
rm -f /tmp/task_result.json 2>/dev/null || true
# We use a simple tar or just copy the directory structure via copy_from_env approach
# Since copy_from_env copies single files, we'll serialize data into the JSON
# or verify file content in the verifier by reading the copied CSVs.
# To make it easy for verifier.py using standard copy_from_env:

# Read file contents into JSON (if they exist and are small enough)
# Note: CSVs are small text files, safe to embed.
AGENT_CSV_CONTENT=""
if [ "$OUTPUT_EXISTS" = "true" ]; then
    AGENT_CSV_CONTENT=$(cat "$OUTPUT_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    AGENT_CSV_CONTENT="null"
fi

GT_CSV_CONTENT=""
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GT_CSV_CONTENT=$(cat "$GROUND_TRUTH_PATH" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    GT_CSV_CONTENT="null"
fi

cat > /tmp/task_result.json << EOF
{
    "metadata": {
        "task_start": $TASK_START,
        "output_exists": $OUTPUT_EXISTS,
        "file_created_during_task": $FILE_CREATED_DURING_TASK,
        "output_size_bytes": $OUTPUT_SIZE
    },
    "agent_csv_content": $AGENT_CSV_CONTENT,
    "ground_truth_csv_content": $GT_CSV_CONTENT
}
EOF

chmod 666 /tmp/task_result.json

echo "=== Export complete ==="