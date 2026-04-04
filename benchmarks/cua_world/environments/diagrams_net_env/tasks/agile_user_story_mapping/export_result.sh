#!/bin/bash
echo "=== Exporting User Story Map Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DRAWIO_PATH="/home/ga/Diagrams/lumina_story_map.drawio"
PNG_PATH="/home/ga/Diagrams/lumina_story_map.png"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Stats
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"modified\": true, \"size\": $size, \"path\": \"$fpath\"}"
        else
            echo "{\"exists\": true, \"modified\": false, \"size\": $size, \"path\": \"$fpath\"}"
        fi
    else
        echo "{\"exists\": false, \"modified\": false, \"size\": 0, \"path\": \"$fpath\"}"
    fi
}

DRAWIO_STATS=$(check_file "$DRAWIO_PATH")
PNG_STATS=$(check_file "$PNG_PATH")

# 3. Create Result JSON
# We copy the raw drawio file to a temp location to avoid permission issues during copy_from_env
if [ -f "$DRAWIO_PATH" ]; then
    cp "$DRAWIO_PATH" /tmp/submission.drawio
    chmod 644 /tmp/submission.drawio
fi

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "drawio_file": $DRAWIO_STATS,
    "png_file": $PNG_STATS,
    "submission_path": "/tmp/submission.drawio"
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json

echo "Export completed. Result:"
cat /tmp/task_result.json