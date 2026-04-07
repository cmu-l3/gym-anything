#!/bin/bash
echo "=== Exporting compute_corridor_emissions result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

STATS_PATH="/home/ga/SUMO_Output/statistics.xml"
REPORT_PATH="/home/ga/SUMO_Output/emissions_report.txt"

# Check Statistics XML
if [ -f "$STATS_PATH" ]; then
    STATS_EXISTS="true"
    STATS_MTIME=$(stat -c %Y "$STATS_PATH" 2>/dev/null || echo "0")
    STATS_SIZE=$(stat -c %s "$STATS_PATH" 2>/dev/null || echo "0")
else
    STATS_EXISTS="false"
    STATS_MTIME="0"
    STATS_SIZE="0"
fi

# Check Report TXT
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
else
    REPORT_EXISTS="false"
    REPORT_MTIME="0"
    REPORT_SIZE="0"
fi

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "stats_exists": $STATS_EXISTS,
    "stats_mtime": $STATS_MTIME,
    "stats_size_bytes": $STATS_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_size_bytes": $REPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="