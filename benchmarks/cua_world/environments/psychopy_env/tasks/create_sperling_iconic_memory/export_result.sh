#!/bin/bash
echo "=== Exporting Sperling Iconic Memory result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/sperling_task.psyexp"
COND_FILE="/home/ga/PsychoPyExperiments/conditions/sperling_conditions.csv"
RESULT_FILE="/tmp/sperling_result.json"

# Basic file stats
EXP_EXISTS="false"
COND_EXISTS="false"
EXP_SIZE=0
COND_SIZE=0
EXP_MODIFIED="false"
COND_MODIFIED="false"

TASK_START=$(get_task_start)

if [ -f "$EXP_FILE" ]; then
    EXP_EXISTS="true"
    EXP_SIZE=$(stat -c %s "$EXP_FILE")
    if was_modified_after_start "$EXP_FILE"; then
        EXP_MODIFIED="true"
    fi
fi

if [ -f "$COND_FILE" ]; then
    COND_EXISTS="true"
    COND_SIZE=$(stat -c %s "$COND_FILE")
    if was_modified_after_start "$COND_FILE"; then
        COND_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "experiment_exists": $EXP_EXISTS,
    "conditions_exists": $COND_EXISTS,
    "experiment_size": $EXP_SIZE,
    "conditions_size": $COND_SIZE,
    "experiment_modified": $EXP_MODIFIED,
    "conditions_modified": $COND_MODIFIED,
    "task_start_time": $TASK_START,
    "result_nonce": "$(get_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f "$RESULT_FILE" 2>/dev/null || true
mv "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"