#!/bin/bash
set -e
echo "=== Exporting import_csv_column_mapping task results ==="

export DISPLAY="${DISPLAY:-:1}"

# Take final screenshot
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/final_state.png 2>/dev/null || true

# Gather file metrics
SSRF_PATH="/home/ga/Documents/dives.ssrf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/ssrf_initial_mtime.txt 2>/dev/null || echo "0")

CURRENT_MTIME=0
FILE_EXISTS="false"
FILE_MODIFIED="false"

if [ -f "$SSRF_PATH" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c%Y "$SSRF_PATH" 2>/dev/null || echo "0")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Write metadata JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "ssrf_initial_mtime": $INITIAL_MTIME,
    "ssrf_current_mtime": $CURRENT_MTIME,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED
}
EOF

chmod 644 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
echo "=== Task export complete ==="