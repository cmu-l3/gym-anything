#!/bin/bash
echo "=== Exporting HP Filter Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Define output paths
OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_FILE="$OUTPUT_DIR/hp_analysis.inp"
DATA_FILE="$OUTPUT_DIR/usa_hp_decomposed.gdt"
REPORT_FILE="$OUTPUT_DIR/hp_report.txt"

# 3. Gather file existence and metadata
get_file_info() {
    local f="$1"
    if [ -f "$f" ]; then
        echo "{\"exists\": true, \"size\": $(stat -c%s "$f"), \"mtime\": $(stat -c%Y "$f")}"
    else
        echo "{\"exists\": false, \"size\": 0, \"mtime\": 0}"
    fi
}

# 4. Read report content if it exists (safely)
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    # Read first 1KB, escape quotes/backslashes
    REPORT_CONTENT=$(head -c 1024 "$REPORT_FILE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    REPORT_CONTENT="\"\""
fi

# 5. Check if Gretl is still running
APP_RUNNING="false"
if is_gretl_running; then
    APP_RUNNING="true"
fi

# 6. Create result JSON
# Note: We do not try to parse the GDT file here; the verifier will do that.
# We just verify file presence and timestamps.
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "files": {
        "script": $(get_file_info "$SCRIPT_FILE"),
        "dataset": $(get_file_info "$DATA_FILE"),
        "report": $(get_file_info "$REPORT_FILE")
    },
    "report_content_preview": $REPORT_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Set permissions for verifier to read
chmod 644 /tmp/task_result.json
chmod 644 "$SCRIPT_FILE" 2>/dev/null || true
chmod 644 "$DATA_FILE" 2>/dev/null || true
chmod 644 "$REPORT_FILE" 2>/dev/null || true

echo "Export complete. Result summary:"
cat /tmp/task_result.json