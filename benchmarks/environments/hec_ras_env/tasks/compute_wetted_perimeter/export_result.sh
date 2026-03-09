#!/bin/bash
echo "=== Exporting compute_wetted_perimeter results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/wetted_perimeter_analysis.csv"
SUMMARY_PATH="$RESULTS_DIR/wetted_perimeter_summary.txt"

# 1. Check CSV File
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    else
        CSV_CREATED_DURING_TASK="false"
    fi
else
    CSV_EXISTS="false"
    CSV_SIZE="0"
    CSV_CREATED_DURING_TASK="false"
fi

# 2. Check Summary File
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    
    if [ "$SUMMARY_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    else
        SUMMARY_CREATED_DURING_TASK="false"
    fi
else
    SUMMARY_EXISTS="false"
    SUMMARY_CREATED_DURING_TASK="false"
fi

# 3. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_created_during_task": $SUMMARY_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
echo "=== Export complete ==="