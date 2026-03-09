#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Report Results ==="

# Define paths
DOCS_DIR="/home/ga/Documents/Presentations"
ODP_PATH="$DOCS_DIR/monthly_review.odp"

# Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Focus window to ensure shortcuts work (if app still open)
wid=$(get_impress_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    # Attempt to save just in case user forgot
    # safe_xdotool ga :1 key ctrl+s
    # sleep 2
    # Close application
    safe_xdotool ga :1 key ctrl+q
    sleep 2
fi

# Gather file statistics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$ODP_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ODP_PATH")
    FILE_MTIME=$(stat -c %Y "$ODP_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Export result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "file_path": "$ODP_PATH",
    "timestamp": "$(date +%s)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="