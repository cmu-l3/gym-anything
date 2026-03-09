#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Mirror Dance Video Result ==="

TASK_NAME="mirror_dance_video"
OUTPUT_FILE="/home/ga/Videos/dance_demo_mirrored.mp4"
EXPORT_FILE="/tmp/vlc_mirror_dance_output.mp4"

# Check for the output video file
if [ -f "${OUTPUT_FILE}" ]; then
    echo "✅ [${TASK_NAME}] Output video found: ${OUTPUT_FILE}"
    cp "${OUTPUT_FILE}" "${EXPORT_FILE}"
    
    # Get file size for logging
    OUTPUT_SIZE=$(stat -f%z "${OUTPUT_FILE}" 2>/dev/null || stat -c%s "${OUTPUT_FILE}" 2>/dev/null || echo "0")
    echo "   File size: ${OUTPUT_SIZE} bytes"
    
    # Get video info using ffprobe if available
    if command -v ffprobe &> /dev/null; then
        echo "   Video properties:"
        ffprobe -v error -show_entries stream=codec_name,width,height,duration \
                -show_entries format=duration,size \
                -of default=noprint_wrappers=1 \
                "${OUTPUT_FILE}" 2>/dev/null | head -10 || true
    fi
    
    ls -lh "${OUTPUT_FILE}"
else
    echo "⚠️  [${TASK_NAME}] Output video not found at expected location: ${OUTPUT_FILE}"
    
    # Look for any recently created video files in Videos directory
    echo "   Searching for recent video files..."
    RECENT_VIDEO=$(find /home/ga/Videos -type f -name "*.mp4" -mmin -10 2>/dev/null | grep -v "dance_demo.mp4" | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "   Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" "${EXPORT_FILE}"
        echo "   Exported alternative video file"
    else
        echo "   No recent video files found"
        # Create empty marker file to indicate no output
        touch "${EXPORT_FILE}.missing"
    fi
fi

# Copy VLC logs if available
if [ -f /tmp/vlc_mirror_dance_task.log ]; then
    cp /tmp/vlc_mirror_dance_task.log /tmp/vlc_mirror_dance_export.log || true
    echo "✅ VLC logs exported"
fi

# Close VLC gracefully
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
        echo "VLC still running, force closing..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_mirror_dance_completed.txt
echo "Task: mirror_dance_video" >> /tmp/vlc_mirror_dance_completed.txt
echo "Output expected: ${OUTPUT_FILE}" >> /tmp/vlc_mirror_dance_completed.txt
echo "Output exists: $([ -f "${OUTPUT_FILE}" ] && echo 'yes' || echo 'no')" >> /tmp/vlc_mirror_dance_completed.txt

# List all files in Videos directory for debugging
echo "" >> /tmp/vlc_mirror_dance_completed.txt
echo "Files in /home/ga/Videos/:" >> /tmp/vlc_mirror_dance_completed.txt
ls -lh /home/ga/Videos/ >> /tmp/vlc_mirror_dance_completed.txt 2>&1 || true

echo "=== Export Complete ==="