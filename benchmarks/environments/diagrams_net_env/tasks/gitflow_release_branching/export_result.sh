#!/bin/bash
echo "=== Exporting GitFlow Task Results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather File Info
DRAWIO_FILE="/home/ga/Diagrams/gitflow_release.drawio"
PNG_FILE="/home/ga/Diagrams/gitflow_release.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local size=$(stat -c %s "$f")
        local mtime=$(stat -c %Y "$f")
        local created_during=$([ "$mtime" -gt "$TASK_START" ] && echo "true" || echo "false")
        echo "\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during"
    else
        echo "\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false"
    fi
}

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "drawio_file": { $(check_file "$DRAWIO_FILE") },
    "png_file": { $(check_file "$PNG_FILE") },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Move to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="