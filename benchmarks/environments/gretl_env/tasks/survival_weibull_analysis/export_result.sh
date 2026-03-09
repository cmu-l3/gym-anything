#!/bin/bash
set -euo pipefail

echo "=== Exporting survival_weibull_analysis result ==="

source /workspace/scripts/task_utils.sh

# 1. Basic Information
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check Output Files
SCRIPT_PATH="/home/ga/Documents/gretl_output/strike_analysis.inp"
REPORT_PATH="/home/ga/Documents/gretl_output/strike_report.txt"

SCRIPT_EXISTS="false"
REPORT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare Result JSON
# We copy the hidden ground truth and the user's report to temp files for the python verifier
# (The python verifier will copy them out of the container)

cp /tmp/ground_truth.json /tmp/ground_truth_export.json 2>/dev/null || echo "{}" > /tmp/ground_truth_export.json
chmod 644 /tmp/ground_truth_export.json

if [ "$REPORT_EXISTS" = "true" ]; then
    cp "$REPORT_PATH" /tmp/user_report_export.txt
    chmod 644 /tmp/user_report_export.txt
fi

if [ "$SCRIPT_EXISTS" = "true" ]; then
    cp "$SCRIPT_PATH" /tmp/user_script_export.inp
    chmod 644 /tmp/user_script_export.inp
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "/tmp/ground_truth_export.json",
    "user_report_path": "/tmp/user_report_export.txt",
    "user_script_path": "/tmp/user_script_export.inp"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="