#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Video Metadata Result ==="

# Check for verification report
REPORT_PATH="/home/ga/Documents/video_verification_report.txt"

if [ -f "$REPORT_PATH" ]; then
    echo "✅ Verification report found: $REPORT_PATH"
    cp "$REPORT_PATH" /tmp/vlc_verification_report.txt
    echo "--- Report Contents ---"
    cat "$REPORT_PATH"
    echo "--- End Report ---"
else
    echo "⚠️ Verification report not found at expected location"
    
    # Look for any recently created text files in Documents
    RECENT_DOC=$(find /home/ga/Documents -type f -name "*.txt" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_DOC" ]; then
        echo "Found recent document: $RECENT_DOC"
        cp "$RECENT_DOC" /tmp/vlc_verification_report.txt
    else
        # Create empty placeholder to avoid verification errors
        echo "No report created by agent" > /tmp/vlc_verification_report.txt
    fi
fi

# Copy the source video for ground truth verification
VIDEO_PATH="/home/ga/Videos/verify/user_submitted_protest.mp4"
if [ -f "$VIDEO_PATH" ]; then
    echo "Copying source video for verification..."
    cp "$VIDEO_PATH" /tmp/vlc_source_video.mp4
else
    echo "⚠️ Source video not found"
fi

# Extract ground truth metadata for verification
if [ -f "$VIDEO_PATH" ]; then
    echo "Extracting ground truth metadata..."
    ffprobe -v quiet -show_format -show_streams -of json "$VIDEO_PATH" > /tmp/vlc_ground_truth.json 2>/dev/null || true
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
echo "Metadata verification task completed" >> /tmp/vlc_metadata_completed.txt

echo "=== Export Complete ==="