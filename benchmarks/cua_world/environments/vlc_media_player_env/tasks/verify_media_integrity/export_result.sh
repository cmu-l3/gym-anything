#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Media Integrity Result ==="

# Check for verification report
REPORT_FILE="/home/ga/Documents/verification_report.txt"
EXPORT_REPORT="/tmp/vlc_verification_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Verification report found: $REPORT_FILE"
    cp "$REPORT_FILE" "$EXPORT_REPORT"
    echo "--- Report Contents ---"
    cat "$EXPORT_REPORT"
    echo "--- End Report ---"
else
    echo "⚠️ Verification report not found at expected location"
    
    # Look for any recently created text files in Documents
    RECENT_REPORT=$(find /home/ga/Documents -type f -name "*.txt" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_REPORT" ]; then
        echo "Found recent report: $RECENT_REPORT"
        cp "$RECENT_REPORT" "$EXPORT_REPORT"
    else
        # Create empty marker so verifier knows report is missing
        echo "REPORT_NOT_FOUND" > "$EXPORT_REPORT"
    fi
fi

# Copy the actual video file for verification
ACTUAL_VIDEO="/home/ga/Videos/verification/documentary_lecture.mp4"
if [ -f "$ACTUAL_VIDEO" ]; then
    cp "$ACTUAL_VIDEO" /tmp/vlc_verification_video.mp4
    echo "✅ Video file copied for verification"
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_verify_integrity_completed.txt
echo "Media verification task completed" >> /tmp/vlc_verify_integrity_completed.txt

echo "=== Export Complete ==="