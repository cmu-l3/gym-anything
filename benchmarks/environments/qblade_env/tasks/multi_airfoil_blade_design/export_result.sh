#!/bin/bash
echo "=== Exporting Multi-Airfoil Blade Design Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather File Statistics
PROJECT_FILE="/home/ga/Documents/projects/multi_airfoil_blade.wpa"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_EXISTS="false"
FILE_SIZE="0"
FILE_CREATED_DURING_TASK="false"
CONTAINS_4421="false"
CONTAINS_4412="false"
CONTAINS_BLADE="false"
CONTAINS_POLAR="false"

if [ -f "$PROJECT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PROJECT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$PROJECT_FILE" 2>/dev/null || echo "0")
    
    # Check timestamp against task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check Content (Grep for keywords in the project file)
    # QBlade project files usually contain definition blocks
    if grep -q "4421" "$PROJECT_FILE"; then CONTAINS_4421="true"; fi
    if grep -q "4412" "$PROJECT_FILE"; then CONTAINS_4412="true"; fi
    
    # Check for Blade definition (look for Blade related tags/keywords)
    if grep -qi "Blade" "$PROJECT_FILE" || grep -qi "Rotor" "$PROJECT_FILE"; then 
        CONTAINS_BLADE="true"
    fi
    
    # Check for Polar data (XFoil results usually labeled)
    if grep -qi "Polar" "$PROJECT_FILE" || grep -qi "XFoil" "$PROJECT_FILE"; then
        CONTAINS_POLAR="true"
    fi
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "contains_4421": $CONTAINS_4421,
    "contains_4412": $CONTAINS_4412,
    "contains_blade_def": $CONTAINS_BLADE,
    "contains_polar_data": $CONTAINS_POLAR,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="