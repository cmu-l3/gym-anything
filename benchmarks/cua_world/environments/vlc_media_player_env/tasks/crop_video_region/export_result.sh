#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Crop Video Region Result ==="

OUTPUT_DIR="/home/ga/Videos/task_output"
EXPECTED_OUTPUT="$OUTPUT_DIR/cropped_video.mp4"

# Check for expected output file
if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "✅ Cropped video found at expected location: $EXPECTED_OUTPUT"
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$EXPECTED_OUTPUT" 2>/dev/null || stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    echo "File size: $((FILE_SIZE / 1024)) KB"
    
    # Copy to /tmp for verification
    cp "$EXPECTED_OUTPUT" /tmp/vlc_cropped_output.mp4
    
    # Get video properties for logging
    if command -v ffprobe >/dev/null 2>&1; then
        echo "Output video properties:"
        ffprobe -v error -select_streams v:0 \
                -show_entries stream=width,height,duration,codec_name \
                -of default=noprint_wrappers=1 \
                "$EXPECTED_OUTPUT" 2>/dev/null || true
    fi
else
    echo "⚠️  Cropped video not found at expected location: $EXPECTED_OUTPUT"
    
    # Look for any recently created video files in output directory
    echo "Searching for recently created video files..."
    
    RECENT_VIDEOS=$(find "$OUTPUT_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 2>/dev/null)
    
    if [ -n "$RECENT_VIDEOS" ]; then
        echo "Found recent video file(s):"
        echo "$RECENT_VIDEOS"
        
        # Take the most recent one
        MOST_RECENT=$(echo "$RECENT_VIDEOS" | head -1)
        echo "Using: $MOST_RECENT"
        
        cp "$MOST_RECENT" /tmp/vlc_cropped_output.mp4
        echo "✅ Copied recent video for verification"
    else
        echo "⚠️  No recent video files found in $OUTPUT_DIR"
        
        # Check if any video file exists at all
        if ls "$OUTPUT_DIR"/*.mp4 2>/dev/null | head -1; then
            FALLBACK=$(ls -t "$OUTPUT_DIR"/*.mp4 2>/dev/null | head -1)
            echo "Found video file: $FALLBACK"
            cp "$FALLBACK" /tmp/vlc_cropped_output.mp4
        fi
    fi
fi

# List output directory contents for debugging
echo ""
echo "Output directory contents:"
ls -lh "$OUTPUT_DIR" 2>/dev/null || echo "Directory empty or not accessible"

# Close VLC if still running
if is_vlc_running; then
    echo ""
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

# Create completion marker
echo "$(date)" > /tmp/vlc_crop_completed.txt
echo "Crop video region task export completed" >> /tmp/vlc_crop_completed.txt
echo "Expected output: $EXPECTED_OUTPUT" >> /tmp/vlc_crop_completed.txt

if [ -f /tmp/vlc_cropped_output.mp4 ]; then
    OUTPUT_SIZE=$(stat -f%z /tmp/vlc_cropped_output.mp4 2>/dev/null || stat -c%s /tmp/vlc_cropped_output.mp4 2>/dev/null || echo "0")
    echo "Exported file size: $((OUTPUT_SIZE / 1024)) KB" >> /tmp/vlc_crop_completed.txt
fi

echo ""
echo "=== Export Complete ==="