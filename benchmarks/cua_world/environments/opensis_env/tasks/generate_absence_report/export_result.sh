#!/bin/bash
set -e
echo "=== Exporting generate_absence_report results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define expected paths
TARGET_FILE="/home/ga/Documents/absence_report.pdf"
DOWNLOAD_DIR="/home/ga/Downloads"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# 3. Check file existence
FILE_EXISTS=false
FILE_SIZE=0
FILE_CREATED_DURING=false

# Helper: check if a file was created after task start
check_timestamp() {
    local fpath=$1
    local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
    if [ "$mtime" -gt "$TASK_START" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# The user might have downloaded it to Downloads and not moved it,
# or moved it as instructed. We prioritize the instructed path.
FINAL_PATH=""

if [ -f "$TARGET_FILE" ]; then
    FINAL_PATH="$TARGET_FILE"
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c %s "$FINAL_PATH")
    FILE_CREATED_DURING=$(check_timestamp "$FINAL_PATH")
else
    # Check Downloads as fallback (partial credit potential, or just for debugging)
    # We look for the most recent PDF
    RECENT_PDF=$(ls -t "$DOWNLOAD_DIR"/*.pdf 2>/dev/null | head -n 1)
    if [ -n "$RECENT_PDF" ]; then
        # Check if it was created during task
        IS_NEW=$(check_timestamp "$RECENT_PDF")
        if [ "$IS_NEW" == "true" ]; then
            FINAL_PATH="$RECENT_PDF"
            echo "Note: File found in Downloads, not Documents."
        fi
    fi
fi

# 4. Prepare JSON result
# We do NOT parse the PDF here (doing it in verifier is safer/easier with python libs)
# We just export metadata.

cat > /tmp/task_result.json <<EOF
{
    "timestamp": "$TIMESTAMP",
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$FINAL_PATH",
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Handle Permissions for Copying
chmod 666 /tmp/task_result.json
if [ -n "$FINAL_PATH" ]; then
    cp "$FINAL_PATH" /tmp/exported_report.pdf
    chmod 666 /tmp/exported_report.pdf
fi

echo "Export complete. Result stored in /tmp/task_result.json"