#!/bin/bash
echo "=== Exporting filter_subset_ttest result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
RESULTS_TXT="/home/ga/Documents/Jamovi/filtered_ttest_results.txt"
OMV_FILE="/home/ga/Documents/Jamovi/ToothGrowth_Filtered.omv"

# Check Results Text File
if [ -f "$RESULTS_TXT" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$RESULTS_TXT" 2>/dev/null || echo "0")
    TXT_SIZE=$(stat -c %s "$RESULTS_TXT" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_FRESH="true"
    else
        TXT_FRESH="false"
    fi
else
    TXT_EXISTS="false"
    TXT_MTIME="0"
    TXT_SIZE="0"
    TXT_FRESH="false"
fi

# Check OMV Project File
if [ -f "$OMV_FILE" ]; then
    OMV_EXISTS="true"
    OMV_MTIME=$(stat -c %Y "$OMV_FILE" 2>/dev/null || echo "0")
    OMV_SIZE=$(stat -c %s "$OMV_FILE" 2>/dev/null || echo "0")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_FRESH="true"
    else
        OMV_FRESH="false"
    fi
else
    OMV_EXISTS="false"
    OMV_MTIME="0"
    OMV_SIZE="0"
    OMV_FRESH="false"
fi

# Check if Jamovi is still running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "results_txt_exists": $TXT_EXISTS,
    "results_txt_fresh": $TXT_FRESH,
    "results_txt_size": $TXT_SIZE,
    "omv_exists": $OMV_EXISTS,
    "omv_fresh": $OMV_FRESH,
    "omv_size": $OMV_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result summary saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="