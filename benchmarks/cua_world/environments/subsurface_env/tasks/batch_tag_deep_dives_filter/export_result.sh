#!/bin/bash
set -e
echo "=== Exporting batch_tag_deep_dives_filter task result ==="

export DISPLAY="${DISPLAY:-:1}"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

# Take final screenshot
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/final_state.png 2>/dev/null || true

# Check file modification
OUTPUT_PATH="/home/ga/Documents/dives.ssrf"
FILE_MODIFIED_DURING_TASK="false"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    CURRENT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$TASK_START" ] || [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE
}
EOF

# Move to final location safely
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="