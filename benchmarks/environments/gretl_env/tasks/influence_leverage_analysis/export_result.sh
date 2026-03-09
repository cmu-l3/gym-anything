#!/bin/bash
echo "=== Exporting Influence Analysis Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_PATH="$OUTPUT_DIR/influence_analysis.inp"
REPORT_PATH="$OUTPUT_DIR/influence_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Script Existence & Metadata
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
SCRIPT_VALID="false"
SCRIPT_OUTPUT=""

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
    
    # 2b. Validate Script using gretlcli (running inside container)
    # We run it in batch mode (-b) to check for syntax errors and OLS execution
    echo "Validating script execution..."
    VALIDATION_LOG="/tmp/script_validation.log"
    if sudo -u ga gretlcli -b "$SCRIPT_PATH" > "$VALIDATION_LOG" 2>&1; then
        SCRIPT_VALID="true"
    else
        SCRIPT_VALID="false"
    fi
    # Capture the first 20 lines of output for the verifier to check OLS results
    SCRIPT_OUTPUT=$(head -n 50 "$VALIDATION_LOG" | base64 -w 0)
fi

# 3. Check Report Existence & Metadata
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content for verification (base64 encoded to be JSON safe)
    REPORT_CONTENT_B64=$(base64 -w 0 "$REPORT_PATH")
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_valid_execution": $SCRIPT_VALID,
    "script_validation_output_b64": "$SCRIPT_OUTPUT",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "report_content_b64": "$REPORT_CONTENT_B64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save Result
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="