#!/bin/bash
echo "=== Exporting BFI Psychometric Scoring Result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_time.txt

# Create metadata about the file to verify it was created during the task
if [ -f "/home/ga/pebl/analysis/bfi_report.json" ]; then
    FILE_MTIME=$(stat -c %Y "/home/ga/pebl/analysis/bfi_report.json" 2>/dev/null || echo "0")
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        echo '{"file_created_during_task": true}' > /tmp/file_metadata.json
    else
        echo '{"file_created_during_task": false}' > /tmp/file_metadata.json
    fi
else
    echo '{"file_created_during_task": false}' > /tmp/file_metadata.json
fi

# Take final screenshot (for visual logs)
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

echo "=== Export complete ==="