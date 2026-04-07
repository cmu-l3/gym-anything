#!/bin/bash
echo "=== Exporting Time-Series Quality Assessment Results ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Look for the agent's report
REPORT_PATH="/home/ga/AstroImages/wasp12b_qc/qc_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -n 50)
    # Escape for JSON
    REPORT_CONTENT=$(echo "$REPORT_CONTENT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}')
fi

# Look for AstroImageJ measurement files (evidence of work)
MEASUREMENT_FILE_EXISTS="false"
MEASUREMENT_FILES=$(find /home/ga -type f \( -name "*Measurements*.xls" -o -name "*Measurements*.csv" -o -name "*.tbl" \) -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

if [ "$MEASUREMENT_FILES" -gt 0 ]; then
    MEASUREMENT_FILE_EXISTS="true"
fi

# Compile JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT",
    "measurements_created": $MEASUREMENT_FILE_EXISTS,
    "num_measurement_files": $MEASUREMENT_FILES
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="