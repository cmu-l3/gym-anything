#!/bin/bash
echo "=== Exporting RPG Dungeon Level Design Results ==="

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check for output files
DRAWIO_FILE="/home/ga/Diagrams/dungeon_map.drawio"
PNG_FILE="/home/ga/Diagrams/dungeon_map.png"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Check .drawio file
if [ -f "$DRAWIO_FILE" ]; then
    DRAWIO_EXISTS=true
    DRAWIO_SIZE=$(stat -c%s "$DRAWIO_FILE")
    DRAWIO_MTIME=$(stat -c%Y "$DRAWIO_FILE")
    if [ "$DRAWIO_MTIME" -gt "$TASK_START" ]; then
        DRAWIO_FRESH=true
    else
        DRAWIO_FRESH=false
    fi
else
    DRAWIO_EXISTS=false
    DRAWIO_SIZE=0
    DRAWIO_FRESH=false
fi

# Check .png file
if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS=true
    PNG_SIZE=$(stat -c%s "$PNG_FILE")
else
    PNG_EXISTS=false
    PNG_SIZE=0
fi

# 3. Create JSON Result
cat > /tmp/task_result.json <<EOF
{
    "drawio_exists": $DRAWIO_EXISTS,
    "drawio_size": $DRAWIO_SIZE,
    "drawio_created_during_task": $DRAWIO_FRESH,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "task_start_timestamp": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 4. Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json