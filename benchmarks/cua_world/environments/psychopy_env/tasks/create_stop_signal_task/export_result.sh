#!/bin/bash
echo "=== Exporting Stop Signal Task Result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end.png

# Prepare paths
EXP_FILE="/home/ga/PsychoPyExperiments/sst_task/stop_signal.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/sst_task/sst_conditions.csv"
RESULT_JSON="/tmp/task_result.json"

# Check file existence and stats
EXP_EXISTS="false"
COND_EXISTS="false"
EXP_SIZE=0
COND_SIZE=0

if [ -f "$EXP_FILE" ]; then
    EXP_EXISTS="true"
    EXP_SIZE=$(stat -c %s "$EXP_FILE")
fi

if [ -f "$COND_FILE" ]; then
    COND_EXISTS="true"
    COND_SIZE=$(stat -c %s "$COND_FILE")
fi

# Get timestamps
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
EXP_MTIME=$(stat -c %Y "$EXP_FILE" 2>/dev/null || echo "0")
COND_MTIME=$(stat -c %Y "$COND_FILE" 2>/dev/null || echo "0")

# Check if modified during task
EXP_MODIFIED="false"
COND_MODIFIED="false"
if [ "$EXP_MTIME" -gt "$TASK_START" ]; then EXP_MODIFIED="true"; fi
if [ "$COND_MTIME" -gt "$TASK_START" ]; then COND_MODIFIED="true"; fi

# Verify PsychoPy was running
PSYCHOPY_RUNNING="false"
if is_psychopy_running; then PSYCHOPY_RUNNING="true"; fi

# Create JSON structure (parsing happens in verifier.py to be robust)
cat > "$RESULT_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "psychopy_running": $PSYCHOPY_RUNNING,
    "files": {
        "experiment": {
            "exists": $EXP_EXISTS,
            "path": "$EXP_FILE",
            "size": $EXP_SIZE,
            "modified_during_task": $EXP_MODIFIED
        },
        "conditions": {
            "exists": $COND_EXISTS,
            "path": "$COND_FILE",
            "size": $COND_SIZE,
            "modified_during_task": $COND_MODIFIED
        }
    }
}
EOF

# Handle permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Export complete. JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"