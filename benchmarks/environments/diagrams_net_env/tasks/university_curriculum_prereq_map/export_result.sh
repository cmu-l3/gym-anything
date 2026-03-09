#!/bin/bash
echo "=== Exporting Task Results ==="

# 1. Record Timestamps & Files
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
DIAGRAM_PATH="/home/ga/Diagrams/ai_curriculum_map.drawio"
PDF_PATH="/home/ga/Diagrams/ai_curriculum_map.pdf"

# 2. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Check Files
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        local modified="false"
        if [ "$mtime" -gt "$TASK_START" ]; then modified="true"; fi
        echo "{\"exists\": true, \"size\": $size, \"modified_during_task\": $modified}"
    else
        echo "{\"exists\": false, \"size\": 0, \"modified_during_task\": false}"
    fi
}

DIAGRAM_STAT=$(check_file "$DIAGRAM_PATH")
PDF_STAT=$(check_file "$PDF_PATH")

# 4. Export result JSON
# We don't analyze XML here because python libs might be missing inside container.
# We will copy the .drawio file out and analyze in verifier.py.
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "diagram_file": $DIAGRAM_STAT,
    "pdf_file": $PDF_STAT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json