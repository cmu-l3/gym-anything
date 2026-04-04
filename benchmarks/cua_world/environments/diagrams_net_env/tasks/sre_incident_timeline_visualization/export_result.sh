#!/bin/bash
set -e

echo "=== Exporting SRE Timeline Results ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DIAGRAM_FILE="/home/ga/Diagrams/incident_timeline.drawio"
PDF_FILE="/home/ga/Diagrams/exports/incident_timeline.pdf"

# Function to get file info
get_file_info() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "\"exists\": true, \"size\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task"
    else
        echo "\"exists\": false, \"size\": 0, \"mtime\": 0, \"created_during_task\": false"
    fi
}

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
# Note: We do NOT parse the XML here because bash XML parsing is fragile.
# We will copy the .drawio file to the host in verifier.py and parse it there.
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "diagram_file": { $(get_file_info "$DIAGRAM_FILE") },
    "pdf_file": { $(get_file_info "$PDF_FILE") },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"