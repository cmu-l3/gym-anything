#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Convert Video Result ==="

# Check for converted video
CONVERTED_VIDEO="/home/ga/Videos/converted/output.avi"

if [ -f "$CONVERTED_VIDEO" ]; then
    echo "✅ Converted video found: $CONVERTED_VIDEO"
    cp "$CONVERTED_VIDEO" /tmp/vlc_converted_video.mp4
    ls -lh "$CONVERTED_VIDEO"
else
    echo "⚠️ Converted video not found at expected location"
    
    # Look for any recently created video in converted directory
    RECENT_VIDEO=$(find /home/ga/Videos/converted -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_converted_video.mp4
    fi
fi

# Close VLC
if is_vlc_running; then
    echo "Closing VLC..."
    safe_xdotool ga :1 key ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_convert_completed.txt

echo "=== Export Complete ==="
