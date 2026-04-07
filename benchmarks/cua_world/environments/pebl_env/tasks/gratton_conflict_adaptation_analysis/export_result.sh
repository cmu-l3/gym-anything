#!/bin/bash
set -euo pipefail

echo "=== Exporting Gratton Analysis Results ==="

# Record end state
date +%s > /tmp/task_end_timestamp
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/pebl/analysis/gratton_report.json"
FILE_CREATED="false"

# Anti-gaming check: Did the file get created/modified DURING the task execution?
if [ -f "$OUTPUT_FILE" ]; then
    MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED="true"
    fi
fi

# Write stats for verifier to pull
cat > /tmp/export_stats.json << EOF
{
    "file_created_during_task": $FILE_CREATED,
    "file_exists": $(if [ -f "$OUTPUT_FILE" ]; then echo "true"; else echo "false"; fi)
}
EOF

# Take final screenshot for visual evidence
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/gratton_final_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="