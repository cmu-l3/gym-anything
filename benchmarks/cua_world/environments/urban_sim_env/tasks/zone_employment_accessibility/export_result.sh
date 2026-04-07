#!/bin/bash
set -e
echo "=== Exporting zone_employment_accessibility result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gather file existence and modification timestamps
check_file() {
    if [ -f "$1" ]; then
        MTIME=$(stat -c %Y "$1" 2>/dev/null || echo "0")
        SIZE=$(stat -c %s "$1" 2>/dev/null || echo "0")
        CREATED_DURING=$([ "$MTIME" -gt "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"mtime\": $MTIME, \"size\": $SIZE, \"created_during_task\": $CREATED_DURING}"
    else
        echo "{\"exists\": false, \"mtime\": 0, \"size\": 0, \"created_during_task\": false}"
    fi
}

CSV_STAT=$(check_file "/home/ga/urbansim_projects/output/zone_accessibility.csv")
PNG_STAT=$(check_file "/home/ga/urbansim_projects/output/accessibility_map.png")
TXT_STAT=$(check_file "/home/ga/urbansim_projects/output/accessibility_summary.txt")
NB_STAT=$(check_file "/home/ga/urbansim_projects/notebooks/employment_accessibility.ipynb")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "files": {
        "csv": $CSV_STAT,
        "png": $PNG_STAT,
        "txt": $TXT_STAT,
        "notebook": $NB_STAT
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="