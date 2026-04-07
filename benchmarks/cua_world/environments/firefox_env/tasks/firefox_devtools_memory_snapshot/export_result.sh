#!/bin/bash
echo "=== Exporting task results ==="

# Record timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target file
OUTPUT_PATH="/home/ga/Documents/heap_analysis.fxsnapshot"

# Initialize verification flags
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
CONTAINS_ENGINE_SIG="false"
CONTAINS_LEAK_SIG="false"

# Check the output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Anti-gaming: Ensure file was created after the task started
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check for SpiderMonkey core dump signatures (verifies it's a real Firefox heap dump)
    # Using 'strings' because the snapshot is a structured binary/JSON format
    if strings "$OUTPUT_PATH" | grep -q -E "allocationStack|js::|JSObject|Window|leakedObjects"; then
        CONTAINS_ENGINE_SIG="true"
    fi

    # Check for the specific leak signature to prove the agent clicked the button FIRST
    if strings "$OUTPUT_PATH" | grep -q "LEAKED_STRING_DATA_"; then
        CONTAINS_LEAK_SIG="true"
    fi
fi

# Capture application state
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Format JSON result securely using a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "contains_engine_sig": $CONTAINS_ENGINE_SIG,
    "contains_leak_sig": $CONTAINS_LEAK_SIG,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="