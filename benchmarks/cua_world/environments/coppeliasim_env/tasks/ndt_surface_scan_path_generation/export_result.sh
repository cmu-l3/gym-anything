#!/bin/bash
set -e
echo "=== Exporting ndt_surface_scan_path_generation Result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/CoppeliaSim/exports/scan_path.csv"
JSON_PATH="/home/ga/Documents/CoppeliaSim/exports/scan_report.json"

# Check CSV existence and timestamp
CSV_EXISTS="false"
CSV_IS_NEW="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
fi

# Check JSON existence and timestamp
JSON_EXISTS="false"
JSON_IS_NEW="false"
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi
fi

# Export metadata bundle. The verifier will copy the actual CSV/JSON for math validation.
TEMP_JSON=$(mktemp /tmp/task_result_meta.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="