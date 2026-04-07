#!/bin/bash
echo "=== Exporting Measure Extended Galaxy Flux Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target paths
CSV_PATH="/home/ga/AstroImages/measurements/roi_measurements.csv"
TXT_PATH="/home/ga/AstroImages/measurements/flux_report.txt"

# Initialize variables
CSV_EXISTS="false"
TXT_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
TXT_MODIFIED_DURING_TASK="false"
REPORTED_AREA=""
REPORTED_INTDEN=""
REPORTED_BGMEAN=""
REPORTED_NETFLUX=""

# Check CSV
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
fi

# Check TXT and extract values
if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_MODIFIED_DURING_TASK="true"
    fi
    
    # Parse the reported values using awk/grep (ignoring case of keys just in case, but expecting standard)
    REPORTED_AREA=$(grep -i "GALAXY_AREA" "$TXT_PATH" | awk -F'[:,=]' '{print $2}' | tr -d '[:space:]' | grep -oE "[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?" || echo "")
    REPORTED_INTDEN=$(grep -i "GALAXY_INTDEN" "$TXT_PATH" | awk -F'[:,=]' '{print $2}' | tr -d '[:space:]' | grep -oE "[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?" || echo "")
    REPORTED_BGMEAN=$(grep -i "BACKGROUND_MEAN" "$TXT_PATH" | awk -F'[:,=]' '{print $2}' | tr -d '[:space:]' | grep -oE "[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?" || echo "")
    REPORTED_NETFLUX=$(grep -i "NET_FLUX" "$TXT_PATH" | awk -F'[:,=]' '{print $2}' | tr -d '[:space:]' | grep -oE "[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?" || echo "")
fi

# Determine if AstroImageJ is still running
APP_RUNNING="false"
if pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# Dump to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "txt_exists": $TXT_EXISTS,
    "csv_modified_during_task": $CSV_MODIFIED_DURING_TASK,
    "txt_modified_during_task": $TXT_MODIFIED_DURING_TASK,
    "app_running": $APP_RUNNING,
    "reported": {
        "galaxy_area": "$REPORTED_AREA",
        "galaxy_intden": "$REPORTED_INTDEN",
        "background_mean": "$REPORTED_BGMEAN",
        "net_flux": "$REPORTED_NETFLUX"
    }
}
EOF

# Copy out to stable location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported JSON Results:"
cat /tmp/task_result.json

echo "=== Export Complete ==="