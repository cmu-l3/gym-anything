#!/bin/bash
echo "=== Exporting evaluate_wake_interaction_two_turbines result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_PATH="/home/ga/Documents/projects/wake_study.wpa"
REPORT_PATH="/home/ga/Documents/wake_loss_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Read content (safe read limit)
    REPORT_CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
fi

# 3. Check if QBlade is running
APP_RUNNING=$(is_qblade_running)
if [ "$APP_RUNNING" != "0" ]; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Extract Project File Content (Partial) for Verification
# We want to see if it contains multiple turbine definitions or specific keywords
# QBlade .wpa files are often XML or text. We'll grab the first 500 lines.
PROJECT_SNIPPET=""
if [ "$PROJECT_EXISTS" = "true" ]; then
    # Grep for turbine instances or position data to keep payload small
    PROJECT_SNIPPET=$(grep -E "Turbine|Position|Location|Instance" "$PROJECT_PATH" | head -n 50 | base64 -w 0)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size": $PROJECT_SIZE,
    "project_snippet_b64": "$PROJECT_SNIPPET",
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="