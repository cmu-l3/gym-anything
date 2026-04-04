#!/bin/bash
echo "=== Exporting fault_tree_drone_power results ==="

DRAWIO_PATH="/home/ga/Desktop/fault_tree.drawio"
PNG_PATH="/home/ga/Desktop/fault_tree.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot (Trajectory evidence)
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check files
DRAWIO_EXISTS="false"
PNG_EXISTS="false"
FILE_MODIFIED="false"
DRAWIO_SIZE="0"

if [ -f "$DRAWIO_PATH" ]; then
    DRAWIO_EXISTS="true"
    DRAWIO_SIZE=$(stat -c %s "$DRAWIO_PATH")
    MTIME=$(stat -c %Y "$DRAWIO_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
fi

# 3. Create Result JSON
# We don't parse XML here; we let the python verifier do the heavy lifting
# by copying the file out. We just report metadata here.

cat > /tmp/task_result.json << EOF
{
    "drawio_exists": $DRAWIO_EXISTS,
    "png_exists": $PNG_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "drawio_path": "$DRAWIO_PATH",
    "png_path": "$PNG_PATH",
    "drawio_size": $DRAWIO_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions for copy_from_env
chmod 644 /tmp/task_result.json
if [ -f "$DRAWIO_PATH" ]; then
    chmod 644 "$DRAWIO_PATH"
fi
if [ -f "$PNG_PATH" ]; then
    chmod 644 "$PNG_PATH"
fi

echo "=== Export complete ==="
cat /tmp/task_result.json