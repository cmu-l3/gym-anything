#!/bin/bash
echo "=== Exporting create_chemical_pid results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
EDDX_PATH="/home/ga/Diagrams/pid_unit100.eddx"
PDF_PATH="/home/ga/Diagrams/pid_unit100.pdf"

# Function to check file status
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true|$size"
        else
            echo "false|$size" # Exists but old (shouldn't happen due to setup cleanup)
        fi
    else
        echo "false|0"
    fi
}

# Check EDDX file
IFS='|' read -r EDDX_CREATED EDDX_SIZE <<< "$(check_file "$EDDX_PATH")"

# Check PDF file
IFS='|' read -r PDF_CREATED PDF_SIZE <<< "$(check_file "$PDF_PATH")"

# Check if application is running
APP_RUNNING=$(is_edrawmax_running && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "eddx_exists": $([ -f "$EDDX_PATH" ] && echo "true" || echo "false"),
    "eddx_created_during_task": $EDDX_CREATED,
    "eddx_size_bytes": $EDDX_SIZE,
    "eddx_path": "$EDDX_PATH",
    "pdf_exists": $([ -f "$PDF_PATH" ] && echo "true" || echo "false"),
    "pdf_created_during_task": $PDF_CREATED,
    "pdf_size_bytes": $PDF_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="