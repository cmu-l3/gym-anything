#!/bin/bash
echo "=== Exporting logistic_feature_creation_hierarchical results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_PATH="/home/ga/Documents/Jamovi/ExamPass_LogReg.omv"
RESULTS_PATH="/home/ga/Documents/Jamovi/model_results.txt"

# Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
fi

# Check Results Text File
RESULTS_EXISTS="false"
RESULTS_CONTENT=""
if [ -f "$RESULTS_PATH" ]; then
    RESULTS_EXISTS="true"
    RESULTS_CONTENT=$(cat "$RESULTS_PATH" | head -n 5) # Read first few lines
fi

# Check if App is running
APP_RUNNING="false"
if pgrep -f "jamovi" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "results_exists": $RESULTS_EXISTS,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# If text file exists, copy it to a temp location readable by verifier (copy_from_env)
if [ "$RESULTS_EXISTS" = "true" ]; then
    cp "$RESULTS_PATH" /tmp/model_results_export.txt
    chmod 666 /tmp/model_results_export.txt
fi

# If project exists, copy it for verification
if [ "$PROJECT_EXISTS" = "true" ]; then
    cp "$PROJECT_PATH" /tmp/project_export.omv
    chmod 666 /tmp/project_export.omv
fi

echo "=== Export complete ==="