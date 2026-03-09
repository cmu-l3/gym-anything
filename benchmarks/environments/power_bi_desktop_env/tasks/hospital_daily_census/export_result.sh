#!/bin/bash
echo "=== Exporting Hospital Census Results ==="

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PBIX_PATH="/home/ga/Desktop/Hospital_Census.pbix"
CSV_PATH="/home/ga/Desktop/daily_census_export.csv"
GT_PATH="/var/lib/powerbi/hospital_ground_truth.csv"

# Check PBIX
PBIX_EXISTS="false"
PBIX_SIZE="0"
if [ -f "$PBIX_PATH" ]; then
    PBIX_MTIME=$(stat -c %Y "$PBIX_PATH")
    if [ "$PBIX_MTIME" -gt "$TASK_START" ]; then
        PBIX_EXISTS="true"
        PBIX_SIZE=$(stat -c %s "$PBIX_PATH")
    fi
fi

# Check CSV
CSV_EXISTS="false"
CSV_SIZE="0"
if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c %s "$CSV_PATH")
    fi
fi

# Check App State
APP_RUNNING=$(pgrep -f "PBIDesktop" > /dev/null && echo "true" || echo "false")

# Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# JSON Result Construction
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pbix_exists": $PBIX_EXISTS,
    "pbix_size": $PBIX_SIZE,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "app_running": $APP_RUNNING,
    "ground_truth_path": "$GT_PATH",
    "agent_csv_path": "$CSV_PATH"
}
EOF

# Move result to readable location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"