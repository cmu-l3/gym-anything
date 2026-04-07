#!/bin/bash
echo "=== Exporting build_shape_verification_legacy result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

EXP_FILE="/home/ga/PsychoPyExperiments/shape_task.psyexp"
CSV_FILE="/home/ga/PsychoPyExperiments/legacy_conditions.csv"

# Verify files exist
EXP_EXISTS="false"
CSV_EXISTS="false"
[ -f "$EXP_FILE" ] && EXP_EXISTS="true"
[ -f "$CSV_FILE" ] && CSV_EXISTS="true"

# Capture file stats
EXP_SIZE=$(stat -c%s "$EXP_FILE" 2>/dev/null || echo "0")
CSV_SIZE=$(stat -c%s "$CSV_FILE" 2>/dev/null || echo "0")
CSV_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")

# Create a temporary JSON result
cat > /tmp/task_result.json << EOF
{
    "exp_exists": $EXP_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "exp_path": "$EXP_FILE",
    "csv_path": "$CSV_FILE",
    "exp_size": $EXP_SIZE,
    "csv_size": $CSV_SIZE,
    "csv_mtime": $CSV_MTIME,
    "task_start_time": $(get_task_start),
    "result_nonce": "$(get_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# We do NOT parse the XML/CSV here in bash. 
# We rely on verifier.py to copy the files out and inspect them robustly.

echo "Result JSON created at /tmp/task_result.json"
echo "=== Export complete ==="