#!/bin/bash
echo "=== Exporting Ultimatum Game task results ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority scrot /tmp/task_final.png 2>/dev/null || true

# Stat the output file to check timestamps for anti-gaming in verifier
OUTPUT_FILE="/home/ga/pebl/analysis/ultimatum_report.json"
if [ -f "$OUTPUT_FILE" ]; then
    stat -c %Y "$OUTPUT_FILE" > /tmp/report_mtime.txt 2>/dev/null || echo "0" > /tmp/report_mtime.txt
else
    echo "0" > /tmp/report_mtime.txt
fi

echo "=== Export complete ==="