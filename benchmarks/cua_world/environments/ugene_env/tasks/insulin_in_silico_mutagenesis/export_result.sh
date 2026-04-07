#!/bin/bash
echo "=== Exporting insulin_in_silico_mutagenesis results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"
GB_FILE="$RESULTS_DIR/insulin_aspart_mutant.gb"
REPORT_FILE="$RESULTS_DIR/mutagenesis_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# Check Application State
APP_RUNNING="false"
if pgrep -f "ugene" > /dev/null; then
    APP_RUNNING="true"
fi

# Check GenBank file
GB_EXISTS="false"
GB_CREATED_DURING_TASK="false"
GB_SIZE=0

if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
    
    if [ "$GB_MTIME" -gt "$TASK_START" ]; then
        GB_CREATED_DURING_TASK="true"
    fi
fi

# Check Report file
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# Generate JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "gb_file_exists": $GB_EXISTS,
    "gb_created_during_task": $GB_CREATED_DURING_TASK,
    "gb_size_bytes": $GB_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="