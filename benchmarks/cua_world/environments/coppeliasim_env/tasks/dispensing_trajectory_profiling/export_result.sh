#!/bin/bash
echo "=== Exporting dispensing_trajectory_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/CoppeliaSim/exports/dispensing_profile.csv"
JSON_PATH="/home/ga/Documents/CoppeliaSim/exports/dispensing_report.json"

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Retrieve file modification times
CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")

# Package meta-results for the verifier
# The actual math validation will be done by the verifier pulling the raw files
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_mtime": $CSV_MTIME,
    "json_mtime": $JSON_MTIME,
    "csv_path": "$CSV_PATH",
    "json_path": "$JSON_PATH"
}
EOF

# Move to final location securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export Complete ==="