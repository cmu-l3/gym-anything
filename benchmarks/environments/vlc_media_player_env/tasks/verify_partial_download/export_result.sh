#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Partial Download Result ==="

# Check for report file
REPORT_FILE="/home/ga/Documents/partial_download_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Report found: $REPORT_FILE"
    cp "$REPORT_FILE" /tmp/vlc_partial_download_report.txt
    echo "--- Report Content ---"
    cat "$REPORT_FILE"
    echo "--- End Report ---"
else
    echo "⚠️ Report not found at expected location"
    
    # Search for any text files in Documents created recently
    RECENT_REPORT=$(find /home/ga/Documents -name "*.txt" -mmin -10 -type f 2>/dev/null | head -1)
    
    if [ -n "$RECENT_REPORT" ]; then
        echo "Found recent file: $RECENT_REPORT"
        cp "$RECENT_REPORT" /tmp/vlc_partial_download_report.txt
    else
        # Create empty placeholder so verifier can detect absence
        echo "No report created" > /tmp/vlc_partial_download_report.txt
    fi
fi

# Copy ground truth for verifier
if [ -f /tmp/partial_video_ground_truth.txt ]; then
    cp /tmp/partial_video_ground_truth.txt /tmp/vlc_partial_ground_truth.txt
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

echo "$(date)" > /tmp/vlc_partial_download_completed.txt
echo "Partial download verification task completed" >> /tmp/vlc_partial_download_completed.txt

echo "=== Export Complete ==="