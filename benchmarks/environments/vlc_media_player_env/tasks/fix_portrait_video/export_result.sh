#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Portrait Video Result ==="

# Expected output file
CONVERTED_VIDEO="/home/ga/Videos/corrected/portrait_corrected.mp4"
EXPORT_PATH="/tmp/vlc_portrait_corrected.mp4"

# Check for converted video at expected location
if [ -f "$CONVERTED_VIDEO" ]; then
    echo "✅ Converted video found: $CONVERTED_VIDEO"
    ls -lh "$CONVERTED_VIDEO"
    
    # Get video properties for logging
    echo "Video properties:"
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,duration,codec_name \
        -of default=noprint_wrappers=1 "$CONVERTED_VIDEO" 2>/dev/null || echo "Could not probe video"
    
    # Copy to /tmp for verifier access
    cp "$CONVERTED_VIDEO" "$EXPORT_PATH"
    echo "✅ Copied to $EXPORT_PATH"
else
    echo "⚠️ Converted video not found at expected location: $CONVERTED_VIDEO"
    
    # Search for any recently created video files in corrected directory
    echo "Searching for recent video files in /home/ga/Videos/corrected/..."
    RECENT_VIDEO=$(find /home/ga/Videos/corrected -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        ls -lh "$RECENT_VIDEO"
        cp "$RECENT_VIDEO" "$EXPORT_PATH"
        echo "✅ Copied recent video to $EXPORT_PATH"
    else
        echo "❌ No recent video files found"
        
        # Check if any conversion is still in progress
        if pgrep -f "vlc.*transcode" > /dev/null; then
            echo "⚠️ VLC conversion still in progress..."
            # Wait a bit longer
            sleep 10
            if [ -f "$CONVERTED_VIDEO" ]; then
                cp "$CONVERTED_VIDEO" "$EXPORT_PATH"
                echo "✅ Conversion completed, copied to $EXPORT_PATH"
            fi
        fi
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
echo "$(date)" > /tmp/vlc_portrait_completed.txt
echo "Portrait video conversion task completed" >> /tmp/vlc_portrait_completed.txt

if [ -f "$EXPORT_PATH" ]; then
    echo "Task status: SUCCESS" >> /tmp/vlc_portrait_completed.txt
    echo "Output file size: $(du -h $EXPORT_PATH | cut -f1)" >> /tmp/vlc_portrait_completed.txt
else
    echo "Task status: FAILED - No output file found" >> /tmp/vlc_portrait_completed.txt
fi

echo "=== Export Complete ==="