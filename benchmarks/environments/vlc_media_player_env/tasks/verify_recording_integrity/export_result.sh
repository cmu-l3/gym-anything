#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Recording Integrity Result ==="

# Check for verification report
REPORT_FILE="/home/ga/Videos/recording_verification_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Verification report found: $REPORT_FILE"
    cp "$REPORT_FILE" /tmp/vlc_recording_verification_report.txt
    echo "--- Report Content ---"
    cat "$REPORT_FILE"
    echo "--- End Report ---"
else
    echo "⚠️ Verification report not found at expected location"
    
    # Look for any recently created text files in Videos directory
    RECENT_REPORT=$(find /home/ga/Videos -type f -name "*.txt" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_REPORT" ]; then
        echo "Found recent report: $RECENT_REPORT"
        cp "$RECENT_REPORT" /tmp/vlc_recording_verification_report.txt
    else
        # Create minimal file to avoid verifier error
        echo "No report generated" > /tmp/vlc_recording_verification_report.txt
    fi
fi

# Also copy the recording file info for independent verification
if [ -f /tmp/recording_info.json ]; then
    cp /tmp/recording_info.json /tmp/vlc_recording_file_info.json
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_verify_recording_completed.txt
echo "Report path: $REPORT_FILE" >> /tmp/vlc_verify_recording_completed.txt

echo "=== Export Complete ==="