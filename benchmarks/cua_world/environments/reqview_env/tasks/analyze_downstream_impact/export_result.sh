#!/bin/bash
echo "=== Exporting analyze_downstream_impact results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_PATH=$(cat /tmp/current_project_path.txt 2>/dev/null)

# Default if project path missing
if [ -z "$PROJECT_PATH" ]; then
    PROJECT_PATH="/home/ga/Documents/ReqView/impact_analysis_project"
fi

REPORT_PATH="/home/ga/Documents/ReqView/impact_report.json"
SRS_JSON_PATH="$PROJECT_PATH/documents/SRS.json"

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Application State
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# 3. Prepare files for verification
# We need the SRS.json (to check for comments) and the agent's report
# Copy them to /tmp with known names for the verifier to pick up via copy_from_env

# Copy Agent Report
if [ -f "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" /tmp/verify_report.json
    chmod 644 /tmp/verify_report.json
fi

# Copy SRS Data
if [ -f "$SRS_JSON_PATH" ]; then
    cp "$SRS_JSON_PATH" /tmp/verify_srs.json
    chmod 644 /tmp/verify_srs.json
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "srs_data_available": $([ -f "/tmp/verify_srs.json" ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="