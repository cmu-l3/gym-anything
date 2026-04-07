#!/bin/bash
echo "=== Exporting create_ax_cpt_task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

CSV_FILE="/home/ga/PsychoPyExperiments/conditions/ax_cpt_conditions.csv"
EXP_FILE="/home/ga/PsychoPyExperiments/ax_cpt.psyexp"
RESULT_JSON="/tmp/task_result.json"

# Basic file existence checks
CSV_EXISTS="false"
EXP_EXISTS="false"
CSV_SIZE="0"
EXP_SIZE="0"
CSV_MODIFIED="false"
EXP_MODIFIED="false"

TASK_START=$(get_task_start)

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_FILE")
    CSV_MTIME=$(stat -c %Y "$CSV_FILE")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
fi

if [ -f "$EXP_FILE" ]; then
    EXP_EXISTS="true"
    EXP_SIZE=$(stat -c %s "$EXP_FILE")
    EXP_MTIME=$(stat -c %Y "$EXP_FILE")
    if [ "$EXP_MTIME" -gt "$TASK_START" ]; then
        EXP_MODIFIED="true"
    fi
fi

# Create JSON result with basic metadata
# Detailed content verification happens in verifier.py
cat > "$RESULT_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "csv_size": $CSV_SIZE,
    "exp_exists": $EXP_EXISTS,
    "exp_modified": $EXP_MODIFIED,
    "exp_size": $EXP_SIZE,
    "result_nonce": "$(get_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result metadata saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="