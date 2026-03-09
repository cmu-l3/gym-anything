#!/bin/bash
echo "=== Exporting Determine Optimal RPM result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Task Artifacts
PROJECT_PATH="/home/ga/Documents/projects/rpm_study.wpa"
REPORT_PATH="/home/ga/Documents/projects/optimal_rpm_report.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_MODIFIED="false"
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    MOD_TIME=$(stat -c%Y "$PROJECT_PATH")
    if [ "$MOD_TIME" -gt "$START_TIME" ]; then
        PROJECT_MODIFIED="true"
    fi
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content, escape quotes for JSON
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 2000 | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# Check Application State
APP_RUNNING=$(is_qblade_running)

# 3. Create Result JSON
# We construct the JSON manually to avoid dependencies, ensuring safe string handling
cat > /tmp/task_result.json << EOF
{
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "project_modified_during_task": $PROJECT_MODIFIED,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "task_duration": $(($(date +%s) - $START_TIME)),
    "timestamp": "$(date -Iseconds)"
}
EOF

# 4. Set permissions so host can copy
chmod 644 /tmp/task_result.json
chmod 644 "$PROJECT_PATH" 2>/dev/null || true
chmod 644 "$REPORT_PATH" 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="