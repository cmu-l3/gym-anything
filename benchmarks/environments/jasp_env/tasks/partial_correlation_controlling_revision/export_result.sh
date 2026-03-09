#!/bin/bash
echo "=== Exporting Partial Correlation Results ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_PATH="/home/ga/Documents/JASP/PartialCorrelation_Exam.jasp"

# Check output file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    CREATED_DURING_TASK="false"
fi

# Check if JASP is still running
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Copy the JASP file to a temp location for the verifier to access easily via copy_from_env
# (The verifier might not have access to home/ga directly if permissions are strict, though copy_from_env usually handles absolute paths. 
# Copying to /tmp is safer.)
if [ "$OUTPUT_EXISTS" == "true" ]; then
    cp "$OUTPUT_PATH" /tmp/verification_output.jasp
    chmod 666 /tmp/verification_output.jasp
fi

echo "=== Export complete ==="