#!/bin/bash
echo "=== Exporting lexdec_priming_analysis result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_timestamp

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if output file was created/modified during task
OUTPUT_PATH="/home/ga/pebl/analysis/priming_report.json"
FILE_MODIFIED_DURING_TASK="false"
if [ -f "$OUTPUT_PATH" ]; then
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Buffer added to offset rapid setup-start deltas
    if [ "$OUTPUT_MTIME" -ge "$((TASK_START - 2))" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Write metadata to result JSON
cat > /tmp/task_result.json << EOF
{
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"