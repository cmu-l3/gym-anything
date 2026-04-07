#!/bin/bash
echo "=== Exporting generate_bulletin_scbulletin results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE doing any processing
take_screenshot /tmp/task_final_state.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_OUTPUT="/home/ga/bulletins/noto_bulletin.txt"
ACTUAL_OUTPUT=""

OUTPUT_EXISTS="false"
FILE_CREATED="false"
OUTPUT_SIZE="0"

# Check expected location
if [ -f "$EXPECTED_OUTPUT" ]; then
    ACTUAL_OUTPUT="$EXPECTED_OUTPUT"
else
    # Check alternate realistic locations if agent messed up the path slightly
    ALT1="/home/ga/noto_bulletin.txt"
    ALT2="/home/ga/bulletin.txt"
    if [ -f "$ALT1" ]; then
        ACTUAL_OUTPUT="$ALT1"
    elif [ -f "$ALT2" ]; then
        ACTUAL_OUTPUT="$ALT2"
    fi
fi

if [ -n "$ACTUAL_OUTPUT" ] && [ -f "$ACTUAL_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$ACTUAL_OUTPUT" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ACTUAL_OUTPUT" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
    
    # Copy file to a safe location for verifier to pull
    cp "$ACTUAL_OUTPUT" /tmp/agent_bulletin.txt
    chmod 666 /tmp/agent_bulletin.txt
fi

# Retrieve ground truth
GT_EVENT_ID=$(cat /tmp/ground_truth/event_id.txt 2>/dev/null || echo "unknown")

# Create JSON payload
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED,
    "output_size_bytes": $OUTPUT_SIZE,
    "bulletin_path": "$ACTUAL_OUTPUT",
    "gt_event_id": "$GT_EVENT_ID",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="