#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Test Capture Devices Result ==="

# Get task start time for filtering
TASK_START=$(cat /tmp/vlc_capture_task_start.txt 2>/dev/null || echo "0")
echo "Task started at timestamp: $TASK_START"

# Find recently created video files in Videos directory
VIDEOS_DIR="/home/ga/Videos"
RECORDING_FILE=""

echo "Searching for recording files..."

# Look for VLC recording files (vlc-record-* pattern)
for file in "$VIDEOS_DIR"/vlc-record-*.{mp4,avi,mkv} "$VIDEOS_DIR"/*.{mp4,avi,mkv,mov}; do
    if [ -f "$file" ]; then
        FILE_TIME=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        
        # Check if file was created after task start (with 5s buffer)
        if [ "$FILE_TIME" -ge $((TASK_START - 5)) ]; then
            FILE_SIZE=$(stat -c %s "$file" 2>/dev/null || echo "0")
            
            # Skip very small files (likely incomplete)
            if [ "$FILE_SIZE" -gt 10000 ]; then
                echo "✅ Found candidate recording: $file"
                echo "   Size: $FILE_SIZE bytes, Modified: $(date -d @$FILE_TIME)"
                
                # Use most recent file
                if [ -z "$RECORDING_FILE" ] || [ "$FILE_TIME" -gt "$(stat -c %Y "$RECORDING_FILE" 2>/dev/null || echo 0)" ]; then
                    RECORDING_FILE="$file"
                fi
            fi
        fi
    fi
done

# Copy recording if found
if [ -n "$RECORDING_FILE" ] && [ -f "$RECORDING_FILE" ]; then
    echo "✅ Selected recording: $RECORDING_FILE"
    
    # Get file extension
    FILE_EXT="${RECORDING_FILE##*.}"
    
    # Copy to /tmp with standard name
    cp "$RECORDING_FILE" /tmp/vlc_capture_recording."$FILE_EXT"
    
    # Also create symlink with .mp4 extension for compatibility
    ln -sf /tmp/vlc_capture_recording."$FILE_EXT" /tmp/vlc_capture_recording.mp4
    
    echo "✅ Recording copied to /tmp/vlc_capture_recording.$FILE_EXT"
    ls -lh "/tmp/vlc_capture_recording.$FILE_EXT"
    
    # Get basic info with ffprobe if available
    if command -v ffprobe > /dev/null 2>&1; then
        echo ""
        echo "📊 Recording info:"
        ffprobe -v error -show_entries format=duration,size,bit_rate \
            -show_entries stream=codec_name,codec_type,width,height \
            -of default=noprint_wrappers=1 \
            "$RECORDING_FILE" 2>/dev/null || echo "Could not analyze with ffprobe"
    fi
else
    echo "⚠️  No recording file found in $VIDEOS_DIR"
    echo "Searching all video files modified in last 10 minutes:"
    find "$VIDEOS_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 -ls || echo "No recent video files"
fi

# Stop any background ffmpeg processes feeding test device
pkill -f "ffmpeg.*testsrc" || true

# Close VLC
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
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_capture_completed.txt
echo "Recording file: ${RECORDING_FILE:-not_found}" >> /tmp/vlc_capture_completed.txt
echo "Task completed at: $(date)" >> /tmp/vlc_capture_completed.txt

echo "=== Export Complete ==="