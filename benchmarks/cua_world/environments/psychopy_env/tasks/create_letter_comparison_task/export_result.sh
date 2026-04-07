#!/bin/bash
echo "=== Exporting Letter Comparison Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

EXP_FILE="/home/ga/PsychoPyExperiments/letter_comparison/letter_comparison.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/letter_comparison/conditions.csv"

# Check file existence and timestamps
EXP_EXISTS="false"
EXP_MODIFIED="false"
COND_EXISTS="false"
COND_MODIFIED="false"

TASK_START=$(get_task_start)

if [ -f "$EXP_FILE" ]; then
    EXP_EXISTS="true"
    MTIME=$(stat -c %Y "$EXP_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        EXP_MODIFIED="true"
    fi
fi

if [ -f "$COND_FILE" ]; then
    COND_EXISTS="true"
    MTIME=$(stat -c %Y "$COND_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        COND_MODIFIED="true"
    fi
fi

# Check if PsychoPy is still running
APP_RUNNING=$(pgrep -f "psychopy" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "exp_exists": $EXP_EXISTS,
    "exp_modified": $EXP_MODIFIED,
    "cond_exists": $COND_EXISTS,
    "cond_modified": $COND_MODIFIED,
    "app_running": $APP_RUNNING,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="