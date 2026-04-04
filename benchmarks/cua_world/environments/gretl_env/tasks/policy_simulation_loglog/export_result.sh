#!/bin/bash
set -euo pipefail

echo "=== Exporting Policy Simulation Results ==="

source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Paths
SCRIPT_PATH="/home/ga/Documents/gretl_output/simulation_script.inp"
RESULT_PATH="/home/ga/Documents/gretl_output/aggregate_impact.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# check files
SCRIPT_EXISTS="false"
SCRIPT_VALID="false"
RESULT_EXISTS="false"
RESULT_CONTENT=""

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_EXISTS="true"
        # Basic content check
        if grep -qi "ols" "$SCRIPT_PATH" && grep -qi "exp" "$SCRIPT_PATH"; then
            SCRIPT_VALID="true"
        fi
    fi
fi

if [ -f "$RESULT_PATH" ]; then
    RESULT_MTIME=$(stat -c %Y "$RESULT_PATH" 2>/dev/null || echo "0")
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_EXISTS="true"
        RESULT_CONTENT=$(cat "$RESULT_PATH" | head -n 1)
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_valid_content": $SCRIPT_VALID,
    "result_exists": $RESULT_EXISTS,
    "result_value_str": "$RESULT_CONTENT",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result: /tmp/task_result.json"