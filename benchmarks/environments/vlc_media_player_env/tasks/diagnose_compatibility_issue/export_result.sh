#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Diagnose Compatibility Issue Result ==="

# Check for diagnostic report file
REPORT_FILE="/home/ga/Documents/video_diagnostic_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Diagnostic report found: $REPORT_FILE"
    echo "--- Report Contents ---"
    cat "$REPORT_FILE"
    echo "--- End Report ---"
    
    # Copy to expected location for verifier
    cp "$REPORT_FILE" /tmp/vlc_diagnostic_report.txt
    
    # Log file size
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    echo "Report size: $REPORT_SIZE bytes"
else
    echo "⚠️ Diagnostic report not found at expected location: $REPORT_FILE"
    
    # Check alternative locations
    echo "Checking for report files in Documents directory..."
    find /home/ga/Documents -type f -name "*.txt" -mmin -10 2>/dev/null | while read -r file; do
        echo "Found recent text file: $file"
        cat "$file"
    done
    
    # Check if any file was modified recently in Documents
    RECENT_FILE=$(find /home/ga/Documents -type f -mmin -10 2>/dev/null | head -1)
    if [ -n "$RECENT_FILE" ]; then
        echo "Found recently modified file: $RECENT_FILE"
        cp "$RECENT_FILE" /tmp/vlc_diagnostic_report.txt
    fi
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Ensure VLC is fully closed
kill_vlc ga 2>/dev/null || true

echo "$(date)" > /tmp/vlc_diagnose_completed.txt
echo "Diagnostic task completed" >> /tmp/vlc_diagnose_completed.txt

echo "=== Export Complete ==="