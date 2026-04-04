#!/bin/bash
echo "=== Exporting feature_engineering_survival_analysis results ==="

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define Paths
PROJECT_PATH="/home/ga/Documents/Jamovi/Titanic_FeatureEng.omv"
REPORT_PATH="/home/ga/Documents/Jamovi/survival_rates.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# 3. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    # Check modification time to ensure it was saved during the task
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH")
    if [ "$PROJECT_MTIME" -gt "$START_TIME" ]; then
        PROJECT_FRESH="true"
    else
        PROJECT_FRESH="false"
    fi
else
    PROJECT_FRESH="false"
fi

# 4. Check Report File
REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    # Read content for debug/logging (verifier will parse it separately)
    echo "Report content:"
    cat "$REPORT_PATH"
fi

# 5. Check App Status
APP_RUNNING="false"
if pgrep -f "org.jamovi.jamovi" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $START_TIME,
    "task_end": $END_TIME,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "project_fresh": $PROJECT_FRESH,
    "report_exists": $REPORT_EXISTS,
    "report_path": "$REPORT_PATH",
    "dataset_path": "/home/ga/Documents/Jamovi/TitanicSurvival.csv",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Safe Move
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export complete ==="