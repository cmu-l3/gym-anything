#!/bin/bash
echo "=== Exporting computed_variable_efficiency results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EXPECTED_CSV="/home/ga/Documents/JASP/efficiency_data.csv"
EXPECTED_JASP="/home/ga/Documents/JASP/efficiency_analysis.jasp"

# 1. Check CSV Export
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_MTIME="0"
if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$EXPECTED_CSV")
    CSV_MTIME=$(stat -c %Y "$EXPECTED_CSV")
fi

# 2. Check JASP Project Save
JASP_EXISTS="false"
JASP_SIZE="0"
JASP_MTIME="0"
if [ -f "$EXPECTED_JASP" ]; then
    JASP_EXISTS="true"
    JASP_SIZE=$(stat -c %s "$EXPECTED_JASP")
    JASP_MTIME=$(stat -c %Y "$EXPECTED_JASP")
fi

# 3. Check App Status
APP_RUNNING=$(pgrep -f "org.jaspstats.JASP" > /dev/null && echo "true" || echo "false")

# 4. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_mtime": $CSV_MTIME,
    "csv_path": "$EXPECTED_CSV",
    "jasp_exists": $JASP_EXISTS,
    "jasp_size": $JASP_SIZE,
    "jasp_mtime": $JASP_MTIME,
    "jasp_path": "$EXPECTED_JASP",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="