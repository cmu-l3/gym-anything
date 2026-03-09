#!/bin/bash
echo "=== Exporting spectral_analysis_gdp_cycles results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DATA_PATH="/home/ga/Documents/gretl_output/periodogram_data.txt"
PLOT_PATH="/home/ga/Documents/gretl_output/periodogram_plot.png"

# Check Data File
if [ -f "$DATA_PATH" ]; then
    DATA_EXISTS="true"
    DATA_SIZE=$(stat -c %s "$DATA_PATH" 2>/dev/null || echo "0")
    DATA_MTIME=$(stat -c %Y "$DATA_PATH" 2>/dev/null || echo "0")
    
    if [ "$DATA_MTIME" -gt "$TASK_START" ]; then
        DATA_CREATED_DURING_TASK="true"
    else
        DATA_CREATED_DURING_TASK="false"
    fi
else
    DATA_EXISTS="false"
    DATA_SIZE="0"
    DATA_CREATED_DURING_TASK="false"
fi

# Check Plot File
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_SIZE=$(stat -c %s "$PLOT_PATH" 2>/dev/null || echo "0")
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING_TASK="true"
    else
        PLOT_CREATED_DURING_TASK="false"
    fi
else
    PLOT_EXISTS="false"
    PLOT_SIZE="0"
    PLOT_CREATED_DURING_TASK="false"
fi

# Check if Gretl is still running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "data_exists": $DATA_EXISTS,
    "data_created_during_task": $DATA_CREATED_DURING_TASK,
    "data_size_bytes": $DATA_SIZE,
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING_TASK,
    "plot_size_bytes": $PLOT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"