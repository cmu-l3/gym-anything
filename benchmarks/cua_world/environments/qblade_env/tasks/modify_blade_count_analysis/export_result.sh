#!/bin/bash
echo "=== Exporting Modify Blade Count Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
PROJECT_PATH="/home/ga/Documents/projects/two_blade_analysis.wpa"
REPORT_PATH="/home/ga/Documents/projects/blade_count_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check Project File
PROJ_EXISTS="false"
PROJ_SIZE=0
PROJ_NEW="false"
if [ -f "$PROJECT_PATH" ]; then
    PROJ_EXISTS="true"
    PROJ_SIZE=$(stat -c%s "$PROJECT_PATH")
    PROJ_MTIME=$(stat -c%Y "$PROJECT_PATH")
    
    if [ "$PROJ_MTIME" -gt "$TASK_START" ]; then
        PROJ_NEW="true"
    fi
fi

# 4. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_NEW="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
    
    # Read content safely (first 5 lines)
    REPORT_CONTENT=$(head -n 5 "$REPORT_PATH" | tr '\n' '|')
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_NEW="true"
    fi
fi

# 5. Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)
if [ "$APP_RUNNING" -gt 0 ]; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 6. Create JSON result
# Note: We rely on the python verifier to parse the actual WPA XML content
# so we just export metadata here. The verifier will copy the actual files.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "project_file": {
        "exists": $PROJ_EXISTS,
        "path": "$PROJECT_PATH",
        "size_bytes": $PROJ_SIZE,
        "created_during_task": $PROJ_NEW
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_PATH",
        "content_preview": "$REPORT_CONTENT",
        "created_during_task": $REPORT_NEW
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="