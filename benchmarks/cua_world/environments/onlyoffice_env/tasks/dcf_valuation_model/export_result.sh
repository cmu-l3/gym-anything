#!/bin/bash
echo "=== Exporting dcf_valuation_model results ==="

# --- Source shared utilities ---
source /workspace/scripts/task_utils.sh

# --- Read task start timestamp ---
TASK_START=$(cat /tmp/dcf_valuation_model_start_ts 2>/dev/null || echo "0")

# --- Take final screenshot ---
scrot /tmp/dcf_valuation_model_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/dcf_valuation_model_final_screenshot.png 2>/dev/null || true

# --- Save and close ONLYOFFICE ---
if pgrep -f "onlyoffice-desktopeditors\|DesktopEditors" > /dev/null 2>&1; then
    echo "ONLYOFFICE is running, saving and closing..."
    focus_onlyoffice_window
    sleep 1
    save_document ga :1
    sleep 2
    close_onlyoffice ga :1
    sleep 2
fi

# Kill if still running
if pgrep -f "onlyoffice-desktopeditors\|DesktopEditors" > /dev/null 2>&1; then
    echo "ONLYOFFICE still running, killing..."
    kill_onlyoffice ga
    sleep 1
fi

# --- Collect output file metadata ---
REPORT_PATH="/home/ga/Documents/Spreadsheets/novapeak_dcf_model.xlsx"

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo "0")
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MTIME="0"
    echo "Output file not found at $REPORT_PATH"
    echo "Files in Spreadsheets directory:"
    ls -la /home/ga/Documents/Spreadsheets/*.xlsx 2>/dev/null || echo "  (none)"
fi

# Check if file was modified during task
if [ "$FILE_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    FILE_MODIFIED="true"
else
    FILE_MODIFIED="false"
fi

# --- Write result JSON ---
cat > /tmp/dcf_valuation_model_result.json << JSONEOF
{
    "task_name": "dcf_valuation_model",
    "task_start_time": "$TASK_START",
    "timestamp": "$(date +%s)",
    "output_file_exists": "$FILE_EXISTS",
    "output_file_size": "$FILE_SIZE",
    "file_modified_during_task": "$FILE_MODIFIED",
    "output_file_path": "$REPORT_PATH"
}
JSONEOF

chmod 666 /tmp/dcf_valuation_model_result.json

echo "=== dcf_valuation_model export complete ==="
echo "Result JSON:"
cat /tmp/dcf_valuation_model_result.json
