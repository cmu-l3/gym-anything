#!/bin/bash
set -e
echo "=== Exporting pebl_multisite_data_harmonization result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_CSV="/home/ga/pebl/data/harmonized_dataset.csv"
OUTPUT_JSON="/home/ga/pebl/analysis/harmonization_report.json"

CSV_EXISTS="false"
JSON_EXISTS="false"

if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
fi
if [ -f "$OUTPUT_JSON" ]; then
    JSON_EXISTS="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "json_exists": $JSON_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="