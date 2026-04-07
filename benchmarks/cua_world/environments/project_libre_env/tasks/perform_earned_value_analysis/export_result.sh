#!/bin/bash
echo "=== Exporting task results ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Define expected paths
XML_PATH="/home/ga/Projects/project_status_update.xml"
PDF_PATH="/home/ga/Projects/earned_value_report.pdf"

# Function to check file stats
check_file() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local size=$(stat -c %s "$fpath")
        local mtime=$(stat -c %Y "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "{\"exists\": true, \"size\": $size, \"created_during_task\": true}"
        else
            echo "{\"exists\": true, \"size\": $size, \"created_during_task\": false}"
        fi
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

# Check XML and PDF
XML_STATS=$(check_file "$XML_PATH")
PDF_STATS=$(check_file "$PDF_PATH")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if App is running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# Prepare files for copy_from_env (copy to /tmp with known names)
if [ -f "$XML_PATH" ]; then
    cp "$XML_PATH" /tmp/result_project.xml
fi

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "xml_file": $XML_STATS,
    "pdf_report": $PDF_STATS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json
chmod 644 /tmp/result_project.xml 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result JSON:"
cat /tmp/task_result.json