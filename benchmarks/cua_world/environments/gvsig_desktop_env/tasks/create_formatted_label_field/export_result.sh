#!/bin/bash
echo "=== Exporting create_formatted_label_field results ==="

source /workspace/scripts/task_utils.sh

# Define paths
DATA_DIR="/home/ga/gvsig_data/countries"
SHP_BASE="ne_110m_admin_0_countries"
DBF_FILE="$DATA_DIR/$SHP_BASE.dbf"

# Capture final screenshot before killing app
take_screenshot /tmp/task_final.png

# Check if gvSIG was running
APP_WAS_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# Kill gvSIG to ensure buffers are flushed to disk (DBF files might be locked or cached)
kill_gvsig

# Gather File Statistics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_dbf_mtime.txt 2>/dev/null || echo "0")
CURRENT_MTIME="0"
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$DBF_FILE" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$DBF_FILE")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Prepare DBF for verification (copy to tmp)
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$DBF_FILE" /tmp/result.dbf
    chmod 644 /tmp/result.dbf
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "dbf_exists": $FILE_EXISTS,
    "dbf_modified": $FILE_MODIFIED,
    "app_was_running": $APP_WAS_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "dbf_path": "/tmp/result.dbf"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="