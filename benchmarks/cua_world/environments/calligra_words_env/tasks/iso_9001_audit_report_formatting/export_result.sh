#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting ISO 9001 Audit Report Formatting Result ==="

WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID" || true
    sleep 1
fi

# Take final screenshot BEFORE closing app
take_screenshot /tmp/task_final.png

# Check if document exists and stat it
OUTPUT_PATH="/home/ga/Documents/apex_iso_audit_report.odt"
if [ -f "$OUTPUT_PATH" ]; then
    stat -c "Saved file: %n (%s bytes, mtime=%Y)" "$OUTPUT_PATH" || true
else
    echo "Warning: $OUTPUT_PATH is missing"
fi

# Try to gracefully prompt agent to save if they forgot, then close
safe_xdotool ga :1 key --delay 200 ctrl+q || true
sleep 3

# Hard kill to release lock files
kill_calligra_processes

echo "=== Export Complete ==="