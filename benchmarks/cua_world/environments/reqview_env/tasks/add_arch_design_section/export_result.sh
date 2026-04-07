#!/bin/bash
echo "=== Exporting add_arch_design_section results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Retrieve project path
PROJECT_PATH=$(cat /tmp/task_project_path.txt 2>/dev/null || echo "/home/ga/Documents/ReqView/add_arch_design_section_project")
ARCH_JSON="$PROJECT_PATH/documents/ARCH.json"

# Check if ARCH file exists and was modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$ARCH_JSON" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ARCH_JSON" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ARCH_JSON" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Copy ARCH.json to temp location for verifier to pick up
    cp "$ARCH_JSON" /tmp/ARCH_final.json
    chmod 666 /tmp/ARCH_final.json
fi

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "arch_file_exists": $FILE_EXISTS,
    "arch_file_modified": $FILE_MODIFIED,
    "arch_file_size": $FILE_SIZE,
    "project_path": "$PROJECT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard result location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"