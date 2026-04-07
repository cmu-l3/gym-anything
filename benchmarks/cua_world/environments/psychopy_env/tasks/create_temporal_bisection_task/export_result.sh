#!/bin/bash
echo "=== Exporting Temporal Bisection Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Paths
EXP_FILE="/home/ga/PsychoPyExperiments/temporal_bisection.psyexp"
ANCHORS_FILE="/home/ga/PsychoPyExperiments/conditions/anchors.csv"
PROBES_FILE="/home/ga/PsychoPyExperiments/conditions/probes.csv"

# Collect file stats
TASK_START=$(get_task_start)
NONCE=$(get_nonce)

# Helper to get file info
get_file_info() {
    local f="$1"
    if [ -f "$f" ]; then
        local size=$(stat -c%s "$f")
        local mtime=$(stat -c%Y "$f")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during\": false}"
    fi
}

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "result_nonce": "$NONCE",
    "timestamp": "$(date -Iseconds)",
    "exp_file": $(get_file_info "$EXP_FILE"),
    "anchors_file": $(get_file_info "$ANCHORS_FILE"),
    "probes_file": $(get_file_info "$PROBES_FILE")
}
EOF

# Copy result file to temp with permissive permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="