#!/bin/bash
echo "=== Exporting create_vertical_vas_rating result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Define file paths
EXP_FILE="/home/ga/PsychoPyExperiments/pain_vas.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/pain_stimuli.csv"
RESULT_JSON="/tmp/task_result.json"

# Capture file metadata
EXP_EXISTS="false"
EXP_SIZE=0
EXP_MTIME=0
COND_EXISTS="false"
COND_SIZE=0
COND_MTIME=0

if [ -f "$EXP_FILE" ]; then
    EXP_EXISTS="true"
    EXP_SIZE=$(stat -c%s "$EXP_FILE")
    EXP_MTIME=$(stat -c%Y "$EXP_FILE")
fi

if [ -f "$COND_FILE" ]; then
    COND_EXISTS="true"
    COND_SIZE=$(stat -c%s "$COND_FILE")
    COND_MTIME=$(stat -c%Y "$COND_FILE")
fi

# Get task start info
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
NONCE=$(cat /home/ga/.task_nonce 2>/dev/null || echo "")

# Check if PsychoPy is running
PSYCHOPY_RUNNING="false"
if is_psychopy_running; then
    PSYCHOPY_RUNNING="true"
fi

# Create result JSON
# We don't parse XML here; we let the Python verifier do the heavy lifting
# by copying the files out via the framework.
cat > "$RESULT_JSON" << EOF
{
    "experiment_exists": $EXP_EXISTS,
    "experiment_size": $EXP_SIZE,
    "experiment_mtime": $EXP_MTIME,
    "conditions_exists": $COND_EXISTS,
    "conditions_size": $COND_SIZE,
    "conditions_mtime": $COND_MTIME,
    "task_start_time": $TASK_START,
    "result_nonce": "$NONCE",
    "psychopy_running": $PSYCHOPY_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result JSON created:"
cat "$RESULT_JSON"
echo "=== Export complete ==="