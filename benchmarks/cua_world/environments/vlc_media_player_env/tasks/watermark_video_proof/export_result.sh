#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Watermark Video Proof Result ==="

# Expected output file
OUTPUT_VIDEO="/home/ga/Videos/client_preview_watermarked.mp4"
INPUT_VIDEO="/home/ga/Videos/client_preview_raw.mp4"

# Check for watermarked video at expected location
if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Watermarked video found: $OUTPUT_VIDEO"
    cp "$OUTPUT_VIDEO" /tmp/vlc_watermarked_video.mp4
    ls -lh "$OUTPUT_VIDEO"
    
    # Get video info
    echo "Output video info:"
    ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_VIDEO" 2>/dev/null || echo "Duration: unknown"
else
    echo "⚠️ Watermarked video not found at expected location: $OUTPUT_VIDEO"
    
    # Look for any recently created video files in Videos directory
    echo "Searching for recent video files..."
    RECENT_VIDEO=$(find /home/ga/Videos -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 ! -name "client_preview_raw.mp4" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_watermarked_video.mp4
        ls -lh "$RECENT_VIDEO"
    else
        echo "❌ No recent video files found"
        touch /tmp/vlc_watermarked_video.mp4  # Create empty file to avoid verification errors
    fi
fi

# Also copy input video for verification comparison
if [ -f "$INPUT_VIDEO" ]; then
    cp "$INPUT_VIDEO" /tmp/vlc_watermark_input.mp4
    echo "✅ Input video copied for verification"
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
        sleep 1
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_watermark_completed.txt
echo "Watermark video task completed" >> /tmp/vlc_watermark_completed.txt

echo "=== Export Complete ==="