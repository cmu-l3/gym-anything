#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Apply Audio Fadeout Result ==="

OUTPUT_VIDEO="/home/ga/Videos/bedtime_story_fadeout.mp4"

# Check if output file exists
if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Output video found: $OUTPUT_VIDEO"
    
    # Get file info
    FILE_SIZE=$(du -h "$OUTPUT_VIDEO" | cut -f1)
    echo "   File size: $FILE_SIZE"
    
    # Verify file is valid
    if su - ga -c "ffprobe -v error '$OUTPUT_VIDEO' > /dev/null 2>&1"; then
        echo "   ✅ File is valid and playable"
        
        # Get duration
        DURATION=$(su - ga -c "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 '$OUTPUT_VIDEO' 2>/dev/null" || echo "unknown")
        echo "   Duration: ${DURATION}s"
    else
        echo "   ⚠️ File may be corrupted"
    fi
    
    # Copy to temp location for verification
    cp "$OUTPUT_VIDEO" /tmp/vlc_fadeout_output.mp4
    echo "   Copied to /tmp/vlc_fadeout_output.mp4"
else
    echo "⚠️ Output video not found at: $OUTPUT_VIDEO"
    
    # Look for any recently created video files
    echo "Searching for recent video files..."
    RECENT_VIDEO=$(find /home/ga/Videos -name "*.mp4" -mmin -10 -type f 2>/dev/null | grep -v bedtime_story.mp4 | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_fadeout_output.mp4
    else
        echo "No recent video files found"
    fi
fi

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_fadeout_completed.txt
echo "Audio fadeout task export completed" >> /tmp/vlc_fadeout_completed.txt

echo "=== Export Complete ==="