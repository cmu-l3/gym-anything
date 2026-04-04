#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Deinterlace Vintage Footage Result ==="

VIDEO_DIR="/home/ga/Videos"
SOURCE_FILE="$VIDEO_DIR/family_vhs_1995.avi"
OUTPUT_FILE="$VIDEO_DIR/family_vhs_1995_deinterlaced.mp4"

# Check for converted/deinterlaced video at expected location
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Deinterlaced video found: $OUTPUT_FILE"
    
    # Get file info
    FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo "   Size: $FILE_SIZE"
    
    # Get video properties using ffprobe
    if command -v ffprobe >/dev/null 2>&1; then
        DURATION=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
          -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
        CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
          -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
        FIELD_ORDER=$(ffprobe -v error -select_streams v:0 -show_entries stream=field_order \
          -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
        
        echo "   Duration: ${DURATION}s"
        echo "   Codec: $CODEC"
        echo "   Field order: $FIELD_ORDER"
    fi
    
    # Copy to temp location for verification
    cp "$OUTPUT_FILE" /tmp/vlc_deinterlaced_output.mp4
    echo "✅ Output copied to /tmp/vlc_deinterlaced_output.mp4"
else
    echo "⚠️ Expected deinterlaced video not found at: $OUTPUT_FILE"
    
    # Look for any recently created video files in the directory
    echo "Searching for recently created videos in $VIDEO_DIR..."
    RECENT_VIDEO=$(find "$VIDEO_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) \
      -mmin -10 ! -name "family_vhs_1995.avi" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ] && [ -f "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_deinterlaced_output.mp4
        echo "⚠️ Using this as output for verification"
    else
        echo "❌ No output video found"
    fi
fi

# Also copy source for comparison during verification
if [ -f "$SOURCE_FILE" ]; then
    cp "$SOURCE_FILE" /tmp/vlc_deinterlace_source.avi
    echo "✅ Source copied for verification"
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
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker with metadata
cat > /tmp/vlc_deinterlace_completed.txt <<EOF
Deinterlace Vintage Footage Task Completed
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Source: $SOURCE_FILE
Expected output: $OUTPUT_FILE
Output exists: $([ -f "$OUTPUT_FILE" ] && echo "YES" || echo "NO")
EOF

if [ -f "$OUTPUT_FILE" ]; then
    echo "Output size: $(du -h "$OUTPUT_FILE" | cut -f1)" >> /tmp/vlc_deinterlace_completed.txt
fi

echo "✅ Completion marker created"
cat /tmp/vlc_deinterlace_completed.txt

echo "=== Export Complete ==="