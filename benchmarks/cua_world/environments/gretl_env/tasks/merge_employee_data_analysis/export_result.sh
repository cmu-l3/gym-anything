#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Define paths
RESULTS_TXT="/home/ga/Documents/gretl_output/wage_gap_results.txt"
MERGED_GDT="/home/ga/Documents/gretl_output/merged_data.gdt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check Results Text File
RESULTS_EXISTS="false"
RESULTS_CREATED_DURING="false"
RESULTS_SIZE="0"

if [ -f "$RESULTS_TXT" ]; then
    RESULTS_EXISTS="true"
    RESULTS_SIZE=$(stat -c %s "$RESULTS_TXT" 2>/dev/null || echo "0")
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_TXT" 2>/dev/null || echo "0")
    if [ "$RESULTS_MTIME" -gt "$TASK_START" ]; then
        RESULTS_CREATED_DURING="true"
    fi
fi

# Check Merged Data File
GDT_EXISTS="false"
GDT_CREATED_DURING="false"
GDT_SIZE="0"

if [ -f "$MERGED_GDT" ]; then
    GDT_EXISTS="true"
    GDT_SIZE=$(stat -c %s "$MERGED_GDT" 2>/dev/null || echo "0")
    GDT_MTIME=$(stat -c %Y "$MERGED_GDT" 2>/dev/null || echo "0")
    if [ "$GDT_MTIME" -gt "$TASK_START" ]; then
        GDT_CREATED_DURING="true"
    fi
fi

# App Status
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "results_txt_exists": $RESULTS_EXISTS,
    "results_txt_created_during_task": $RESULTS_CREATED_DURING,
    "results_txt_size": $RESULTS_SIZE,
    "merged_gdt_exists": $GDT_EXISTS,
    "merged_gdt_created_during_task": $GDT_CREATED_DURING,
    "merged_gdt_size": $GDT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Summary:"
cat /tmp/task_result.json