#!/bin/bash
echo "=== Exporting insert_math_equations result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TARGET_FILE="/home/ga/Documents/Presentations/classical_mechanics.odp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_SIZE=$(cat /tmp/initial_file_size.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE_INCREASED="false"
CURRENT_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check modification time
    MTIME=$(stat -c %Y "$TARGET_FILE")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check size
    CURRENT_SIZE=$(stat -c %s "$TARGET_FILE")
    if [ "$CURRENT_SIZE" -gt "$INITIAL_SIZE" ]; then
        FILE_SIZE_INCREASED="true"
    fi
fi

# 3. Check if Impress is running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Prepare result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_increased": $FILE_SIZE_INCREASED,
    "initial_size": $INITIAL_SIZE,
    "current_size": $CURRENT_SIZE,
    "app_running": $APP_RUNNING,
    "target_path": "$TARGET_FILE"
}
EOF

# 5. Copy ODP file to temp for verifier access (handle permissions)
if [ -f "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" /tmp/verification_file.odp
    chmod 644 /tmp/verification_file.odp
fi

chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
echo "Verification file at /tmp/verification_file.odp"
echo "=== Export complete ==="