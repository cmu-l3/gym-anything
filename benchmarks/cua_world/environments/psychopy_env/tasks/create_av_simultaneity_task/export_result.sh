#!/bin/bash
echo "=== Exporting AV Simultaneity Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Capture file stats
EXP_FILE="/home/ga/PsychoPyExperiments/av_simultaneity.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/soa_conditions.csv"

# Check existence and modification
EXP_EXISTS="false"
COND_EXISTS="false"
EXP_SIZE=0
COND_SIZE=0
EXP_MODIFIED="false"
COND_MODIFIED="false"

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

if [ -f "$EXP_FILE" ]; then
    EXP_EXISTS="true"
    EXP_SIZE=$(stat -c %s "$EXP_FILE")
    MTIME=$(stat -c %Y "$EXP_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        EXP_MODIFIED="true"
    fi
fi

if [ -f "$COND_FILE" ]; then
    COND_EXISTS="true"
    COND_SIZE=$(stat -c %s "$COND_FILE")
    MTIME=$(stat -c %Y "$COND_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        COND_MODIFIED="true"
    fi
fi

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "exp_exists": $EXP_EXISTS,
    "cond_exists": $COND_EXISTS,
    "exp_size": $EXP_SIZE,
    "cond_size": $COND_SIZE,
    "exp_modified": $EXP_MODIFIED,
    "cond_modified": $COND_MODIFIED,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result summary generated."
cat /tmp/task_result.json