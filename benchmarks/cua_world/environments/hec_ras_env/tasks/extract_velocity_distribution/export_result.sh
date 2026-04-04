#!/bin/bash
echo "=== Exporting extract_velocity_distribution results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/velocity_distribution.csv"
SUMMARY_PATH="$RESULTS_DIR/velocity_summary.txt"

# Check CSV file
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE="0"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Check Summary file
SUMMARY_EXISTS="false"
SUMMARY_CREATED_DURING_TASK="false"
SUMMARY_SIZE="0"

if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    SUMMARY_SIZE=$(stat -c %s "$SUMMARY_PATH" 2>/dev/null || echo "0")
    
    if [ "$SUMMARY_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    fi
fi

# Check for Python scripts created by agent
SCRIPT_COUNT=$(find /home/ga -name "*.py" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# Check bash history for relevant commands
HISTORY_MATCH="false"
if grep -qi "h5py\|hdf\|velocity" /home/ga/.bash_history 2>/dev/null; then
    HISTORY_MATCH="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create metadata JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size_bytes": $CSV_SIZE,
    "csv_path": "$CSV_PATH",
    "summary_exists": $SUMMARY_EXISTS,
    "summary_created_during_task": $SUMMARY_CREATED_DURING_TASK,
    "summary_size_bytes": $SUMMARY_SIZE,
    "summary_path": "$SUMMARY_PATH",
    "agent_scripts_count": $SCRIPT_COUNT,
    "history_match": $HISTORY_MATCH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="