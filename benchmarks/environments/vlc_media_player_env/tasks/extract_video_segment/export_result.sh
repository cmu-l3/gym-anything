#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Extract Video Segment Result ==="

# Get task start time for verification
TASK_START_TIME=$(cat /tmp/vlc_segment_task_start.txt 2>/dev/null || echo "0")

# Look for VLC recordings in Videos directory
VIDEOS_DIR="/home/ga/Videos"
RECORDING_FOUND="false"
RECORDING_FILE=""

echo "Searching for VLC recordings in $VIDEOS_DIR..."

# Find recordings created after task start
# VLC naming patterns: vlc-record-YYYY-MM-DD-HHhMMmSSs-*.mp4 (or .avi, .mkv)
for pattern in "vlc-record-*.mp4" "vlc-record-*.avi" "vlc-record-*.mkv"; do
    while IFS= read -r -d '' file; do
        FILE_MTIME=$(stat -c %Y "$file" 2>/dev/null || echo "0")
        
        if [ "$FILE_MTIME" -gt "$TASK_START_TIME" ]; then
            RECORDING_FOUND="true"
            RECORDING_FILE="$file"
            echo "✅ Found recording: $(basename "$file") ($(du -h "$file" | cut -f1))"
            break 2
        fi
    done < <(find "$VIDEOS_DIR" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)
done

if [ "$RECORDING_FOUND" = "true" ] && [ -f "$RECORDING_FILE" ]; then
    echo "Copying recording to /tmp for verification..."
    cp "$RECORDING_FILE" /tmp/vlc_extracted_segment.mp4
    
    # Get file info
    FILE_SIZE=$(stat -c %s "$RECORDING_FILE" 2>/dev/null || echo "0")
    FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
    
    echo "Recording details:"
    echo "  - Path: $RECORDING_FILE"
    echo "  - Size: $FILE_SIZE_MB MB"
    
    # Try to get duration using ffprobe if available
    if command -v ffprobe &> /dev/null; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$RECORDING_FILE" 2>/dev/null || echo "unknown")
        if [ "$DURATION" != "unknown" ]; then
            DURATION_SEC=$(printf "%.1f" "$DURATION")
            echo "  - Duration: ${DURATION_SEC}s"
        fi
    fi
else
    echo "⚠️  No VLC recording found"
    echo "Checked patterns: vlc-record-*.mp4, vlc-record-*.avi, vlc-record-*.mkv"
    echo "Task start time: $TASK_START_TIME ($(date -d @$TASK_START_TIME 2>/dev/null || echo 'unknown'))"
    
    # List all files for debugging
    echo "All files in $VIDEOS_DIR:"
    ls -lht "$VIDEOS_DIR" | head -20 || true
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_segment_completed.txt
echo "Task start: $TASK_START_TIME" >> /tmp/vlc_segment_completed.txt
echo "Recording found: $RECORDING_FOUND" >> /tmp/vlc_segment_completed.txt
if [ "$RECORDING_FOUND" = "true" ]; then
    echo "Recording file: $(basename "$RECORDING_FILE")" >> /tmp/vlc_segment_completed.txt
fi

echo "=== Export Complete ==="