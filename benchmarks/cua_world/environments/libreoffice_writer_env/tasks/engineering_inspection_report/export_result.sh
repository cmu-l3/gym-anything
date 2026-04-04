#!/bin/bash
# export_result.sh — Engineering Inspection Report Task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Engineering Inspection Report Result ==="

wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

if [ -f "/home/ga/Documents/inspection_report.docx" ]; then
    echo "Output file found: /home/ga/Documents/inspection_report.docx"
    ls -lh /home/ga/Documents/inspection_report.docx
else
    echo "WARNING: Output file not found at /home/ga/Documents/inspection_report.docx"
fi

echo "Closing LibreOffice Writer..."
safe_xdotool ga :1 key --delay 200 ctrl+q
sleep 1
safe_xdotool ga :1 key --delay 100 alt+d
sleep 0.5

echo "=== Export Complete ==="
exit 0
