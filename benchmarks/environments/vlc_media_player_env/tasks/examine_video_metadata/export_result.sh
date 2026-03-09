#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Examine Video Metadata Result ==="

# Check for metadata report
REPORT_FILE="/home/ga/Documents/metadata_report.txt"

if [ -f "$REPORT_FILE" ]; then
    echo "✅ Metadata report found: $REPORT_FILE"
    cp "$REPORT_FILE" /tmp/vlc_metadata_report.txt
    echo "--- Report Content ---"
    cat "$REPORT_FILE"
    echo "--- End Report ---"
    
    # Get file size for verification
    REPORT_SIZE=$(wc -c < "$REPORT_FILE")
    echo "Report size: $REPORT_SIZE bytes"
else
    echo "⚠️ Metadata report not found at expected location: $REPORT_FILE"
    
    # Look for any recently created text files in Documents
    RECENT_FILE=$(find /home/ga/Documents -type f -name "*.txt" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_FILE" ]; then
        echo "Found recent text file: $RECENT_FILE"
        cp "$RECENT_FILE" /tmp/vlc_metadata_report.txt
        cat "$RECENT_FILE"
    else
        echo "No recent report files found"
        # Create empty placeholder for verifier
        touch /tmp/vlc_metadata_report.txt
    fi
fi

# Also copy ground truth for verifier
if [ -f /tmp/metadata_ground_truth.json ]; then
    echo "✅ Copying ground truth for verification"
    # Ground truth is already in /tmp, verifier will access it
else
    echo "⚠️ Ground truth file not found"
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

echo "$(date)" > /tmp/vlc_metadata_completed.txt
echo "Metadata examination task completed" >> /tmp/vlc_metadata_completed.txt

echo "=== Export Complete ==="