#!/bin/bash
echo "=== Exporting blade_mesh_independence_study results ==="

source /workspace/scripts/task_utils.sh

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# File paths
REFINED_PROJECT="/home/ga/Documents/projects/refined_turbine.wpa"
REPORT_FILE="/home/ga/Documents/projects/mesh_study_report.txt"

# Check Refined Project
PROJECT_EXISTS="false"
PROJECT_SIZE="0"
if [ -f "$REFINED_PROJECT" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$REFINED_PROJECT")
fi

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read first 5 lines of report
    REPORT_CONTENT=$(head -n 5 "$REPORT_FILE" | base64 -w 0)
fi

# Check if QBlade is running
APP_RUNNING=$(is_qblade_running)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_path": "$REFINED_PROJECT",
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content_b64": "$REPORT_CONTENT",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm "$TEMP_JSON"

echo "=== Export complete ==="