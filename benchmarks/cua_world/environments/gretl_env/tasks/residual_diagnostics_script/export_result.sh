#!/bin/bash
echo "=== Exporting Residual Diagnostics Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_PATH="$OUTPUT_DIR/resid_diagnostics.inp"
REPORT_PATH="$OUTPUT_DIR/diagnostics_report.txt"
PLOT1_PATH="$OUTPUT_DIR/resid_vs_fitted.png"
PLOT2_PATH="$OUTPUT_DIR/resid_histogram.png"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Script Existence and Validity
SCRIPT_EXISTS="false"
SCRIPT_VALID="false"
SCRIPT_EXEC_OUTPUT=""

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    # Verify script is valid by trying to run it in batch mode (dry run or actual)
    # We use -b (batch) and capture exit code
    if gretlcli -b "$SCRIPT_PATH" > /tmp/script_validation.log 2>&1; then
        SCRIPT_VALID="true"
    else
        SCRIPT_VALID="false"
    fi
    SCRIPT_EXEC_OUTPUT=$(head -n 20 /tmp/script_validation.log | base64 -w 0)
fi

# 2. Check Plots
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$f" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ] && [ "$size" -gt 100 ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

PLOT1_VALID=$(check_file "$PLOT1_PATH")
PLOT2_VALID=$(check_file "$PLOT2_PATH")

# 3. Check Report
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    R_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$R_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_valid": $SCRIPT_VALID,
    "script_exec_log_b64": "$SCRIPT_EXEC_OUTPUT",
    "plot1_valid": $PLOT1_VALID,
    "plot2_valid": $PLOT2_VALID,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"