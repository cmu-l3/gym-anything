#!/bin/bash
echo "=== Exporting enforce_tip_speed_safety_limit results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/tip_limited_sim.wpa"
REPORT_PATH="/home/ga/Documents/tip_speed_report.txt"
SCREENSHOT_PATH="/tmp/task_final.png"

# Take final screenshot
take_screenshot "$SCREENSHOT_PATH"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_MODIFIED="false"
PROJECT_SIZE="0"
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_MODIFIED="true"
    fi
    
    # Copy project file to temp for parsing by python verifier
    # (The verifier runs outside, but we need to ensure permissions/access)
    cp "$PROJECT_PATH" /tmp/exported_project.wpa
    chmod 644 /tmp/exported_project.wpa
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content safely, escaping quotes
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    cp "$REPORT_PATH" /tmp/exported_report.txt
    chmod 644 /tmp/exported_report.txt
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "[Qq][Bb]lade" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_modified_during_task": $PROJECT_MODIFIED,
    "project_size_bytes": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content_base64": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "$SCREENSHOT_PATH",
    "project_file_path": "/tmp/exported_project.wpa",
    "report_file_path": "/tmp/exported_report.txt"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="