#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Capture Desktop Result ==="

# Close VLC first to ensure any recording is finalized
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to finalize recording..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3  # Give VLC time to finalize the recording file
fi

# Close gedit as well
pkill -f gedit 2>/dev/null || true

# Get the start time to determine which files were created during task
START_TIME=$(cat /tmp/vlc_capture_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)
TIME_WINDOW=$((CURRENT_TIME - START_TIME + 60))  # Add 60s buffer

echo "Searching for video recordings created in last ${TIME_WINDOW} seconds..."

# Search for recently created video files in common VLC output locations
SEARCH_PATHS=(
    "/home/ga/Videos"
    "/home/ga/Desktop"
    "/home/ga/Pictures"
    "/tmp"
    "/home/ga/.local/share/vlc"
    "/home/ga"
)

# Video extensions to look for
VIDEO_EXTENSIONS=("*.mp4" "*.avi" "*.mkv" "*.ts" "*.mpg" "*.mpeg" "*.mov" "*.flv" "*.wmv")

FOUND_VIDEO=""
NEWEST_TIME=0

for search_path in "${SEARCH_PATHS[@]}"; do
    if [ ! -d "$search_path" ]; then
        continue
    fi
    
    echo "Checking $search_path..."
    
    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        # Find video files modified within our time window
        while IFS= read -r -d '' video_file; do
            if [ -f "$video_file" ]; then
                # Get file modification time
                FILE_TIME=$(stat -c %Y "$video_file" 2>/dev/null || echo "0")
                FILE_SIZE=$(stat -c %s "$video_file" 2>/dev/null || echo "0")
                
                # Check if file was created/modified during task and has reasonable size
                if [ "$FILE_TIME" -ge "$START_TIME" ] && [ "$FILE_SIZE" -gt 102400 ]; then  # > 100KB
                    if [ "$FILE_TIME" -gt "$NEWEST_TIME" ]; then
                        NEWEST_TIME=$FILE_TIME
                        FOUND_VIDEO="$video_file"
                        echo "  Found candidate: $video_file ($(du -h "$video_file" | cut -f1))"
                    fi
                fi
            fi
        done < <(find "$search_path" -maxdepth 2 -name "$ext" -type f -print0 2>/dev/null || true)
    done
done

# If we found a video, copy it to temp location for verification
if [ -n "$FOUND_VIDEO" ] && [ -f "$FOUND_VIDEO" ]; then
    echo "✅ Recording found: $FOUND_VIDEO"
    echo "   Size: $(du -h "$FOUND_VIDEO" | cut -f1)"
    echo "   Modified: $(stat -c %y "$FOUND_VIDEO" | cut -d. -f1)"
    
    cp "$FOUND_VIDEO" /tmp/vlc_desktop_recording.mp4
    
    # Get basic info using ffprobe if available
    if command -v ffprobe &> /dev/null; then
        echo "Video info:"
        ffprobe -v error -show_entries format=duration,size,bit_rate -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "$FOUND_VIDEO" 2>/dev/null || true
    fi
else
    echo "⚠️ No recording found in expected locations"
    echo "Searched paths: ${SEARCH_PATHS[*]}"
    
    # Last resort: find ANY recent video file
    echo "Attempting last resort search..."
    LAST_RESORT=$(find /home/ga -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" -o -name "*.ts" \) -newermt "@$START_TIME" -size +100k 2>/dev/null | head -1)
    
    if [ -n "$LAST_RESORT" ] && [ -f "$LAST_RESORT" ]; then
        echo "Found in last resort: $LAST_RESORT"
        cp "$LAST_RESORT" /tmp/vlc_desktop_recording.mp4
    fi
fi

# Create completion marker with metadata
cat > /tmp/vlc_capture_completed.txt <<EOF
$(date)
Desktop capture task completed
Start time: $START_TIME
End time: $CURRENT_TIME
Recording found: $([ -f /tmp/vlc_desktop_recording.mp4 ] && echo "yes" || echo "no")
EOF

echo "=== Export Complete ==="