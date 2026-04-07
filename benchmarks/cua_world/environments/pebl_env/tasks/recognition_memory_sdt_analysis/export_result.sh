#!/bin/bash
set -e
echo "=== Exporting recognition_memory_sdt_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

REPORT_PATH="/home/ga/pebl/analysis/sdt_report.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_EXISTS="false"
REPORT_MTIME="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# Create metadata JSON
cat > /tmp/task_export.json << EOF
{
    "task_start_time": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME
}
EOF

echo "=== Export complete ==="