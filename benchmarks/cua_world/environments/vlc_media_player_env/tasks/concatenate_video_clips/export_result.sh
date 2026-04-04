#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Concatenate Video Clips Result ==="

# Expected output path
OUTPUT_VIDEO="/home/ga/Videos/merged_output.mp4"

# Check for merged video at expected location
if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Merged video found at expected location: $OUTPUT_VIDEO"
    FILE_SIZE=$(du -h "$OUTPUT_VIDEO" | cut -f1)
    echo "   File size: $FILE_SIZE"
    
    # Copy to /tmp for verification
    cp "$OUTPUT_VIDEO" /tmp/vlc_merged_output.mp4
    echo "   Copied to /tmp/vlc_merged_output.mp4"
else
    echo "⚠️ Merged video not found at expected location: $OUTPUT_VIDEO"
    
    # Search for any recently created MP4 files in Videos directory
    echo "Searching for recent MP4 files in /home/ga/Videos/..."
    RECENT_VIDEO=$(find /home/ga/Videos -maxdepth 1 -type f -name "*.mp4" -mmin -15 2>/dev/null | grep -v "concat_clips" | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        FILE_SIZE=$(du -h "$RECENT_VIDEO" | cut -f1)
        echo "File size: $FILE_SIZE"
        cp "$RECENT_VIDEO" /tmp/vlc_merged_output.mp4
    else
        echo "❌ No recent MP4 files found"
        # Create empty marker to indicate failure
        touch /tmp/vlc_merged_output_not_found.txt
    fi
fi

# Close VLC if still running
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
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_concat_completed.txt
echo "Concatenate video clips task completed" >> /tmp/vlc_concat_completed.txt

# Log statistics
if [ -f /tmp/vlc_merged_output.mp4 ]; then
    echo "Output video statistics:" >> /tmp/vlc_concat_completed.txt
    ffprobe -v error -show_entries format=duration,size,bit_rate -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 /tmp/vlc_merged_output.mp4 >> /tmp/vlc_concat_completed.txt 2>&1 || true
fi

echo "=== Export Complete ==="