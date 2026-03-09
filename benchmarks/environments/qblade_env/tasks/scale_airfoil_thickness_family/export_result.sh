#!/bin/bash
echo "=== Exporting scale_airfoil_thickness_family results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_DIR="/home/ga/Documents/airfoils/family"
PROJECT_FILE="/home/ga/Documents/projects/airfoil_family_scaling.wpa"

# Function to check a specific file
check_file() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local created_during_task="false"
        
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        
        echo "\"$filename\": { \"exists\": true, \"size\": $size, \"created_during_task\": $created_during_task, \"path\": \"$filepath\" }"
    else
        echo "\"$filename\": { \"exists\": false, \"size\": 0, \"created_during_task\": false, \"path\": \"\" }"
    fi
}

# Check Project File
PROJECT_INFO=$(check_file "$PROJECT_FILE")

# Check Airfoil Files
BASE_INFO=$(check_file "$OUTPUT_DIR/base.dat")
ROOT_INFO=$(check_file "$OUTPUT_DIR/root.dat")
TIP_INFO=$(check_file "$OUTPUT_DIR/tip.dat")

# App Running Check
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Construct JSON
# We output the JSON to a temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "project_file": { $PROJECT_INFO },
    "files": {
        $BASE_INFO,
        $ROOT_INFO,
        $TIP_INFO
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="