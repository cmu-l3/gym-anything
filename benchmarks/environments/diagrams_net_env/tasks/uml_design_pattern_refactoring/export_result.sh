#!/bin/bash
echo "=== Exporting UML Refactoring Result ==="

# 1. Capture final state screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define paths
DIAGRAM_PATH="/home/ga/Diagrams/order_system.drawio"
EXPORT_PATH="/home/ga/Diagrams/exports/order_system_refactored.png"

# 3. Check files
FILE_EXISTS="false"
FILE_MODIFIED="false"
EXPORT_EXISTS="false"
EXPORT_SIZE=0

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$DIAGRAM_PATH" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$DIAGRAM_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$EXPORT_PATH" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c %s "$EXPORT_PATH")
    MTIME_EXP=$(stat -c %Y "$EXPORT_PATH")
    if [ "$MTIME_EXP" -le "$TASK_START" ]; then
        # If export is older than start, it's invalid (though we didn't create one in setup)
        EXPORT_EXISTS="false"
    fi
fi

# 4. Create result JSON
# We don't parse the XML here; we let the Python verifier do it via copy_from_env
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "export_exists": $EXPORT_EXISTS,
    "export_size": $EXPORT_SIZE,
    "diagram_path": "$DIAGRAM_PATH",
    "export_path": "$EXPORT_PATH"
}
EOF

# Set permissions so verifier can read it
chmod 644 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"