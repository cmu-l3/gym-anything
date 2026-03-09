#!/bin/bash
echo "=== Exporting tune_blade_stiffness_resonance results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (evidence of QBlade state)
take_screenshot /tmp/task_final.png

# 2. Check for Project File
PROJECT_PATH="/home/ga/Documents/projects/stiffened_blade.wpa"
PROJECT_EXISTS="false"
PROJECT_MODIFIED="false"
PROJECT_SIZE=0

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    
    # Check modification against baseline
    if [ -f /tmp/baseline_project.md5 ]; then
        CURRENT_HASH=$(md5sum "$PROJECT_PATH" | awk '{print $1}')
        BASELINE_HASH=$(awk '{print $1}' /tmp/baseline_project.md5)
        
        if [ "$CURRENT_HASH" != "$BASELINE_HASH" ]; then
            PROJECT_MODIFIED="true"
        fi
    else
        # If no baseline to compare, check timestamp vs start time
        START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
        FILE_TIME=$(stat -c%Y "$PROJECT_PATH")
        if [ "$FILE_TIME" -gt "$START_TIME" ]; then
            PROJECT_MODIFIED="true"
        fi
    fi
fi

# 3. Check for Report File
REPORT_PATH="/home/ga/Documents/projects/resonance_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
EXTRACTED_FREQ=0.0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 500) # Read first 500 chars
    
    # Try to extract frequency number (look for floating point number)
    # Matches: 0.78, 0.8, .85, etc.
    EXTRACTED_FREQ=$(grep -oE "[0-9]*\.[0-9]+" "$REPORT_PATH" | head -1 || echo "0.0")
fi

# 4. Check if QBlade is running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "project_exists": $PROJECT_EXISTS,
    "project_modified": $PROJECT_MODIFIED,
    "project_size": $PROJECT_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo $REPORT_CONTENT | tr -d '\n' | sed 's/"/\\"/g')",
    "reported_frequency": $EXTRACTED_FREQ,
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to public location
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export complete ==="