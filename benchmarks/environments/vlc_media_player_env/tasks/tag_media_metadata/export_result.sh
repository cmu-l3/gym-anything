#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Tag Media Metadata Result ==="

# The modified file should be at the original location
VIDEO_FILE="/home/ga/Videos/concert_recording.mp4"

if [ -f "$VIDEO_FILE" ]; then
    echo "✅ Video file found: $VIDEO_FILE"
    
    # Copy the file for verification
    cp "$VIDEO_FILE" /tmp/vlc_tagged_video.mp4
    
    # Display metadata for debugging (as ga user to avoid permission issues)
    echo "=== Current Metadata ==="
    su - ga -c "ffprobe -v error -show_entries format_tags -of json /home/ga/Videos/concert_recording.mp4 2>/dev/null | jq -r '.format.tags // {}' 2>/dev/null || echo 'No metadata parser available'"
    
    # Get file size
    FILE_SIZE=$(stat -f%z "$VIDEO_FILE" 2>/dev/null || stat -c%s "$VIDEO_FILE" 2>/dev/null || echo "0")
    echo "File size: $FILE_SIZE bytes"
    
else
    echo "❌ Video file not found: $VIDEO_FILE"
    
    # Look for any recently modified video in the directory
    RECENT_VIDEO=$(find /home/ga/Videos -name "*.mp4" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recently modified video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_tagged_video.mp4
    else
        echo "No recently modified videos found"
        exit 1
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
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_metadata_completed.txt
echo "Metadata tagging task completed" >> /tmp/vlc_metadata_completed.txt

echo "=== Export Complete ==="