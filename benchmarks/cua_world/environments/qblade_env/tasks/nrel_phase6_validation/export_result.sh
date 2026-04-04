#!/bin/bash
echo "=== Exporting NREL Phase VI Validation Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Get Task Timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Report File
REPORT_FILE="/home/ga/Documents/nrel_phase6_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_MTIME="0"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
fi

# 4. Check Project File
PROJECT_FILE="/home/ga/Documents/projects/nrel_phase6.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
PROJECT_MTIME="0"
IS_VALID_PROJECT="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_FILE")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_FILE")
    
    # Simple content check
    if grep -q "Blade" "$PROJECT_FILE" && grep -q "Airfoil" "$PROJECT_FILE"; then
        IS_VALID_PROJECT="true"
    fi
fi

# 5. Check App Status
APP_RUNNING=$(is_qblade_running)

# 6. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_content_base64": "$REPORT_CONTENT",
    "report_mtime": $REPORT_MTIME,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "project_mtime": $PROJECT_MTIME,
    "is_valid_project_content": $IS_VALID_PROJECT,
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"