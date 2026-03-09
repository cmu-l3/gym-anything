#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Magnify Distant Subject Result ==="

# Check for magnified video at expected location
OUTPUT_VIDEO="/home/ga/Videos/magnified/bird_closeup.mp4"

if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Magnified video found: $OUTPUT_VIDEO"
    cp "$OUTPUT_VIDEO" /tmp/vlc_magnified_video.mp4
    ls -lh "$OUTPUT_VIDEO"
    
    # Get video info
    echo ""
    echo "Video information:"
    ffprobe -v error -show_entries format=duration,size -show_entries stream=width,height,codec_name -of default=noprint_wrappers=1 "$OUTPUT_VIDEO" 2>&1 | head -10 || true
else
    echo "⚠️  Magnified video not found at expected location: $OUTPUT_VIDEO"
    
    # Look for any recently created video in magnified directory
    MAGNIFIED_DIR="/home/ga/Videos/magnified"
    if [ -d "$MAGNIFIED_DIR" ]; then
        echo "Searching for recent videos in $MAGNIFIED_DIR..."
        RECENT_VIDEO=$(find "$MAGNIFIED_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -5 2>/dev/null | head -1)
        
        if [ -n "$RECENT_VIDEO" ]; then
            echo "Found recent video: $RECENT_VIDEO"
            cp "$RECENT_VIDEO" /tmp/vlc_magnified_video.mp4
            ls -lh "$RECENT_VIDEO"
        else
            echo "No recent videos found in magnified directory"
        fi
    fi
fi

# Also copy original for comparison (useful for debugging)
if [ -f /home/ga/Videos/wildlife_distant_bird.mp4 ]; then
    cp /home/ga/Videos/wildlife_distant_bird.mp4 /tmp/vlc_magnify_original.mp4
    echo "✅ Copied original video for reference"
fi

# Close VLC if still running
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_magnify_completed.txt
echo "Magnify distant subject task completed" >> /tmp/vlc_magnify_completed.txt
echo "Expected output: $OUTPUT_VIDEO" >> /tmp/vlc_magnify_completed.txt

# Check if conversion is still in progress
if pgrep -f "vlc.*transcode" > /dev/null; then
    echo "⚠️  Warning: VLC transcoding may still be in progress"
fi

echo "=== Export Complete ==="