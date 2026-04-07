#!/bin/bash
echo "=== Exporting airfoiled_fin_fabrication_export task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Helper function to check file stats and anti-gaming timestamp
check_file() {
    local path=$1
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$path" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check all required expected outputs
ORK_STATUS=$(check_file "/home/ga/Documents/rockets/upgraded_fins.ork")
OBJ_STATUS=$(check_file "/home/ga/Documents/exports/rocket_3d.obj")
DESIGN_STATUS=$(check_file "/home/ga/Documents/exports/design_report.pdf")
TEMPLATES_STATUS=$(check_file "/home/ga/Documents/exports/fin_templates.pdf")

# Create JSON report
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "files": {
        "ork_file": $ORK_STATUS,
        "obj_file": $OBJ_STATUS,
        "design_report": $DESIGN_STATUS,
        "fin_templates": $TEMPLATES_STATUS
    }
}
EOF

# Make sure it is safely readable
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Task results exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="