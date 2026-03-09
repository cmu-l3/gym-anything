#!/bin/bash
echo "=== Exporting create_pcb_outline_dxf results ==="

# Paths
PROJECT_PATH="/home/ga/Documents/FreeCAD/pcb_outline.FCStd"
DXF_PATH="/home/ga/Documents/FreeCAD/pcb_outline.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to check file status
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local size=$(stat -c %s "$path")
        local mtime=$(stat -c %Y "$path")
        local created_during="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check files
PROJECT_STATUS=$(check_file "$PROJECT_PATH")
DXF_STATUS=$(check_file "$DXF_PATH")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_file": $PROJECT_STATUS,
    "dxf_file": $DXF_STATUS,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Ensure permissions so the host can read it
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="