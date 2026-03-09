#!/bin/bash
echo "=== Exporting Unique Values Symbology Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECT_PATH="/home/ga/gvsig_data/projects/continent_categories.gvsproj"
EXPORT_PATH="/home/ga/gvsig_data/exports/continent_map.png"

# Take final screenshot of the desktop
take_screenshot /tmp/task_final.png

# --- Check Project File ---
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c %s "$PROJECT_PATH")
    PROJECT_MTIME=$(stat -c %Y "$PROJECT_PATH")
    
    # Check if created during task
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_VALID_TIME="true"
    else
        PROJECT_VALID_TIME="false"
    fi
else
    PROJECT_EXISTS="false"
    PROJECT_SIZE="0"
    PROJECT_VALID_TIME="false"
fi

# --- Check Exported Image ---
if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH")
    EXPORT_MTIME=$(stat -c %Y "$EXPORT_PATH")
    
    if [ "$EXPORT_MTIME" -gt "$TASK_START" ]; then
        EXPORT_VALID_TIME="true"
    else
        EXPORT_VALID_TIME="false"
    fi
else
    EXPORT_EXISTS="false"
    EXPORT_SIZE="0"
    EXPORT_VALID_TIME="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_VALID_TIME,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "export_created_during_task": $EXPORT_VALID_TIME,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="