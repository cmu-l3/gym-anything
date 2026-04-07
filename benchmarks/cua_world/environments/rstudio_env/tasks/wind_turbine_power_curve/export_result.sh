#!/bin/bash
echo "=== Exporting wind_turbine_power_curve result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# File paths
CSV_PATH="/home/ga/RProjects/output/empirical_power_curve.csv"
TXT_PATH="/home/ga/RProjects/output/aep_estimation.txt"
PNG_PATH="/home/ga/RProjects/output/power_curve_comparison.png"
SCRIPT_PATH="/home/ga/RProjects/turbine_analysis.R"

# Initialize variables
CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ROWS=0
TXT_EXISTS="false"
TXT_IS_NEW="false"
AEP_VALUE="null"
PNG_EXISTS="false"
PNG_IS_NEW="false"
PNG_SIZE=0
SCRIPT_MODIFIED="false"

# Check CSV
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    [ "$(stat -c %Y "$CSV_PATH")" -gt "$TASK_START" ] && CSV_IS_NEW="true"
    CSV_ROWS=$(awk 'NR>1' "$CSV_PATH" 2>/dev/null | wc -l)
fi

# Check TXT and extract AEP
if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    [ "$(stat -c %Y "$TXT_PATH")" -gt "$TASK_START" ] && TXT_IS_NEW="true"
    
    # Extract first numeric value from text file
    AEP_RAW=$(grep -oE '[0-9]+(\.[0-9]+)?' "$TXT_PATH" | head -1)
    if [ -n "$AEP_RAW" ]; then
        AEP_VALUE="$AEP_RAW"
    fi
fi

# Check PNG
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    [ "$(stat -c %Y "$PNG_PATH")" -gt "$TASK_START" ] && PNG_IS_NEW="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
fi

# Check Script
if [ -f "$SCRIPT_PATH" ]; then
    [ "$(stat -c %Y "$SCRIPT_PATH")" -gt "$TASK_START" ] && SCRIPT_MODIFIED="true"
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_rows": $CSV_ROWS,
    "txt_exists": $TXT_EXISTS,
    "txt_is_new": $TXT_IS_NEW,
    "aep_value": $AEP_VALUE,
    "png_exists": $PNG_EXISTS,
    "png_is_new": $PNG_IS_NEW,
    "png_size_bytes": $PNG_SIZE,
    "script_modified": $SCRIPT_MODIFIED
}
EOF

# Save and export
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="