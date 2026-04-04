#!/bin/bash
echo "=== Exporting data_binning_survival results ==="

# Capture final screenshot immediately
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Definition of paths
PROJECT_PATH="/home/ga/Documents/Jamovi/Titanic_Age_Analysis.omv"
RESULT_PATH="/home/ga/Documents/Jamovi/survival_odds.txt"
DATASET_PATH="/home/ga/Documents/Jamovi/TitanicSurvival.csv"

# Get timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Check Project File (.omv)
PROJECT_EXISTS="false"
PROJECT_CREATED_DURING_TASK="false"
PROJECT_SIZE=0

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# Check Result Text File
RESULT_EXISTS="false"
RESULT_CREATED_DURING_TASK="false"
RESULT_CONTENT=""

if [ -f "$RESULT_PATH" ]; then
    RESULT_EXISTS="true"
    RESULT_MTIME=$(stat -c %Y "$RESULT_PATH")
    if [ "$RESULT_MTIME" -gt "$TASK_START" ]; then
        RESULT_CREATED_DURING_TASK="true"
    fi
    # Read first line only, limit length
    RESULT_CONTENT=$(head -n 1 "$RESULT_PATH" | cut -c 1-20)
fi

# Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "org.jamovi.jamovi" > /dev/null && echo "true" || echo "false")

# Prepare files for the verifier (copy to /tmp/export for easy access if needed, 
# though verifier usually accesses via copy_from_env)
# We strictly use the JSON for metadata.

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_size": $PROJECT_SIZE,
    "result_exists": $RESULT_EXISTS,
    "result_created_during_task": $RESULT_CREATED_DURING_TASK,
    "result_content": "$RESULT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "dataset_path": "$DATASET_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export summary:"
cat /tmp/task_result.json
echo "=== Export complete ==="