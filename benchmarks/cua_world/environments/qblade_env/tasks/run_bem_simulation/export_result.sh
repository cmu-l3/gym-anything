#!/bin/bash
echo "=== Exporting run_bem_simulation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check BEM results file
RESULTS_FILE="/home/ga/Documents/projects/bem_results.txt"
FILE_EXISTS="false"
FILE_LINES=0
HAS_NUMERIC_DATA="false"
HAS_CP_DATA="false"
HAS_TSR_DATA="false"
DATA_POINTS=0

if [ -f "$RESULTS_FILE" ]; then
    FILE_EXISTS="true"
    FILE_LINES=$(wc -l < "$RESULTS_FILE")

    # Count lines with multi-column numeric data (at least 2 decimal columns)
    DATA_POINTS=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*[[:space:]]+-?[0-9]+\.[0-9]+' "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$DATA_POINTS" -gt 3 ]; then
        HAS_NUMERIC_DATA="true"
    fi

    # Check for Cp-related keywords or column headers
    if grep -qiE 'cp|power.*coeff|C_P' "$RESULTS_FILE" 2>/dev/null; then
        HAS_CP_DATA="true"
    fi

    # Check for TSR-related keywords
    if grep -qiE 'tsr|tip.*speed|lambda' "$RESULTS_FILE" 2>/dev/null; then
        HAS_TSR_DATA="true"
    fi
fi

QBLADE_RUNNING=$(is_qblade_running)

RESULT_JSON=$(cat << EOF
{
    "results_file_exists": $FILE_EXISTS,
    "results_file_path": "$RESULTS_FILE",
    "file_lines": $FILE_LINES,
    "has_numeric_data": $HAS_NUMERIC_DATA,
    "has_cp_data": $HAS_CP_DATA,
    "has_tsr_data": $HAS_TSR_DATA,
    "data_points": $DATA_POINTS,
    "qblade_running": $([ "$QBLADE_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$RESULT_JSON"

echo "=== Export complete ==="
