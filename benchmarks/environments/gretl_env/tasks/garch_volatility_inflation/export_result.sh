#!/bin/bash
set -e
echo "=== Exporting GARCH Volatility Inflation results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/gretl_output/garch_inflation.inp"
TXT_PATH="/home/ga/Documents/gretl_output/garch_output.txt"
CSV_PATH="/home/ga/Documents/gretl_output/garch_cond_variance.csv"

# 1. Check Files Existence and Timestamps
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        if [ "$mtime" -ge "$TASK_START" ]; then
            echo "{\"exists\": true, \"size\": $size, \"fresh\": true, \"path\": \"$fpath\"}"
        else
            echo "{\"exists\": true, \"size\": $size, \"fresh\": false, \"path\": \"$fpath\"}"
        fi
    else
        echo "{\"exists\": false, \"size\": 0, \"fresh\": false, \"path\": \"$fpath\"}"
    fi
}

SCRIPT_INFO=$(check_file "$SCRIPT_PATH")
TXT_INFO=$(check_file "$TXT_PATH")
CSV_INFO=$(check_file "$CSV_PATH")

# 2. Validation Run: Attempt to run the agent's script to verify reproducibility
# We run this HERE because verifier.py cannot exec_in_env
VALIDATION_SUCCESS="false"
VALIDATION_LOG="/tmp/validation_run.log"
echo "Running validation of agent script..." > "$VALIDATION_LOG"

if [ -f "$SCRIPT_PATH" ]; then
    # Create a wrapper that ensures we run from the correct directory
    # so relative paths (if used by agent) might work, though absolute is requested
    cd /home/ga/Documents/gretl_output
    
    # Run gretlcli in batch mode
    if gretlcli -b "$SCRIPT_PATH" >> "$VALIDATION_LOG" 2>&1; then
        echo "Script execution return code: 0" >> "$VALIDATION_LOG"
        # Check if the output actually looks like a success (no error messages)
        if ! grep -qi "error" "$VALIDATION_LOG"; then
            VALIDATION_SUCCESS="true"
        fi
    else
        echo "Script execution failed" >> "$VALIDATION_LOG"
    fi
else
    echo "Script file not found, cannot validate." >> "$VALIDATION_LOG"
fi

# 3. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Bundle Results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_file": $SCRIPT_INFO,
    "output_txt": $TXT_INFO,
    "output_csv": $CSV_INFO,
    "validation_run_success": $VALIDATION_SUCCESS,
    "validation_log_path": "$VALIDATION_LOG"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy validation log to a readable location for verifier
cp "$VALIDATION_LOG" /tmp/task_validation.log
chmod 666 /tmp/task_validation.log

echo "=== Export complete ==="