#!/bin/bash
# Export script for Perspective Grid Construction
set -o pipefail

echo "=== Exporting Perspective Grid Result ==="

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TARGET_FILE="/home/ga/Documents/GeoGebra/projects/perspective_grid.ggb"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file status
FILE_FOUND="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE")
    FILE_MTIME=$(stat -c%Y "$TARGET_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy the GGB file to a temp location that is definitely accessible for copy_from_env
    # We rename it to a standard name for the verifier
    cp "$TARGET_FILE" /tmp/result_construction.ggb
    chmod 644 /tmp/result_construction.ggb
else
    # Try to find any recently saved GGB file
    RECENT_FILE=$(find /home/ga/Documents/GeoGebra -name "*.ggb" -type f -newermt "@$TASK_START" | head -n 1)
    if [ -n "$RECENT_FILE" ]; then
        echo "Target file not found, but found recent file: $RECENT_FILE"
        FILE_FOUND="true"
        FILE_CREATED_DURING_TASK="true"
        FILE_SIZE=$(stat -c%s "$RECENT_FILE")
        cp "$RECENT_FILE" /tmp/result_construction.ggb
        chmod 644 /tmp/result_construction.ggb
    fi
fi

# 3. Create Metadata JSON
cat > /tmp/task_result.json <<EOF
{
    "file_found": $FILE_FOUND,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json

echo "Export complete. Result JSON and GGB prepared."