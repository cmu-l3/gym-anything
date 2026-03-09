#!/bin/bash
set -e
echo "=== Exporting Direct Foil Design result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state for VLM
take_screenshot /tmp/task_final.png

# 2. Gather Task Variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_PATH="/home/ga/Documents/projects/custom_spline_foil.wpa"
EXPECTED_NAME="SymCustom15"

# 3. Check File Existence & Stats
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
NAME_FOUND="false"
HAS_SPLINE_DATA="false"

if [ -f "$PROJECT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$PROJECT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PROJECT_PATH" 2>/dev/null || echo "0")
    
    # Check if modified/created after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check for specific airfoil name in the file content
    # WPA files are typically XML-like or INI-like text
    if grep -q "$EXPECTED_NAME" "$PROJECT_PATH"; then
        NAME_FOUND="true"
    fi
    
    # Check for keywords indicating foil data geometry (vs just an empty project)
    # Look for coordinates or spline markers
    if grep -qE "foil|point|coord|spline|0\.[0-9]+" "$PROJECT_PATH" 2>/dev/null; then
        HAS_SPLINE_DATA="true"
    fi
fi

# 4. Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)

# 5. Create JSON Result
# Using a temp file and mv to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$PROJECT_PATH",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "name_found_in_file": $NAME_FOUND,
    "has_data_content": $HAS_SPLINE_DATA,
    "app_was_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false")
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="