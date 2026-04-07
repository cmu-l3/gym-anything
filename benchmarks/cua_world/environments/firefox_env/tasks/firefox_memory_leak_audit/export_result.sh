#!/bin/bash
echo "=== Exporting memory leak audit result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check for snapshot files
# Using find to handle cases where firefox appends extra .fxsnapshot automatically
BASELINE_FILE=$(find /home/ga/Documents -maxdepth 1 -name "baseline*.fxsnapshot*" | head -n 1)
LEAKED_FILE=$(find /home/ga/Documents -maxdepth 1 -name "leaked*.fxsnapshot*" | head -n 1)

BASELINE_EXISTS="false"
BASELINE_SIZE=0
BASELINE_MTIME=0

if [ -n "$BASELINE_FILE" ] && [ -f "$BASELINE_FILE" ]; then
    BASELINE_EXISTS="true"
    BASELINE_SIZE=$(stat -c %s "$BASELINE_FILE" 2>/dev/null || echo "0")
    BASELINE_MTIME=$(stat -c %Y "$BASELINE_FILE" 2>/dev/null || echo "0")
fi

LEAKED_EXISTS="false"
LEAKED_SIZE=0
LEAKED_MTIME=0

if [ -n "$LEAKED_FILE" ] && [ -f "$LEAKED_FILE" ]; then
    LEAKED_EXISTS="true"
    LEAKED_SIZE=$(stat -c %s "$LEAKED_FILE" 2>/dev/null || echo "0")
    LEAKED_MTIME=$(stat -c %Y "$LEAKED_FILE" 2>/dev/null || echo "0")
fi

# Determine if they were created during task
BASELINE_CREATED_DURING="false"
if [ "$BASELINE_MTIME" -gt "$TASK_START" ]; then
    BASELINE_CREATED_DURING="true"
fi

LEAKED_CREATED_DURING="false"
if [ "$LEAKED_MTIME" -gt "$TASK_START" ]; then
    LEAKED_CREATED_DURING="true"
fi

# Final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "baseline_exists": $BASELINE_EXISTS,
    "baseline_size": $BASELINE_SIZE,
    "baseline_created_during_task": $BASELINE_CREATED_DURING,
    "baseline_file": "$BASELINE_FILE",
    "leaked_exists": $LEAKED_EXISTS,
    "leaked_size": $LEAKED_SIZE,
    "leaked_created_during_task": $LEAKED_CREATED_DURING,
    "leaked_file": "$LEAKED_FILE",
    "screenshot_path": "/tmp/task_final.png"
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