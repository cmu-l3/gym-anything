#!/bin/bash
echo "=== Exporting Detect Duplicates Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/duplicate_candidates.json"
SCRIPT_FILE="/home/ga/Documents/detect_duplicates.py"
GROUND_TRUTH_FILE="/var/lib/medintux/ground_truth.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check Output File
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check Script File
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
fi

# Prepare result for export
# We will copy the ground truth to the temp result JSON so the verifier can access it
# (The verifier runs on the host, so it needs this data exported)

# Read Ground Truth content
GT_CONTENT="{}"
if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_CONTENT=$(cat "$GROUND_TRUTH_FILE")
fi

# Read Agent Output content (if valid JSON, otherwise empty)
AGENT_CONTENT="[]"
if [ "$OUTPUT_EXISTS" = "true" ]; then
    # Simple check if valid JSON
    if jq -e . "$OUTPUT_FILE" >/dev/null 2>&1; then
        AGENT_CONTENT=$(cat "$OUTPUT_FILE")
    fi
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "ground_truth": $GT_CONTENT,
    "agent_output": $AGENT_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"