#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Burn Subtitles Result ==="

# Expected output path
OUTPUT_FILE="/home/ga/Videos/converted/film_with_burned_subs.mp4"

# Check for converted video at expected location
if [ -f "$OUTPUT_FILE" ]; then
    echo "✅ Converted video found: $OUTPUT_FILE"
    FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    echo "   File size: $((FILE_SIZE / 1024)) KB"
    
    # Copy to standard output location
    cp "$OUTPUT_FILE" /tmp/vlc_burned_subs_output.mp4
    echo "   Copied to /tmp/vlc_burned_subs_output.mp4"
else
    echo "⚠️ Expected output not found: $OUTPUT_FILE"
    
    # Look for any recently created video files in converted directory
    RECENT_VIDEO=$(find /home/ga/Videos/converted -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "   Found recent video: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_burned_subs_output.mp4
        echo "   Copied alternative output"
    else
        echo "   No recent video files found in output directory"
    fi
fi

# Copy conversion logs if available
if [ -f /tmp/vlc_burn_subs_task.log ]; then
    cp /tmp/vlc_burn_subs_task.log /tmp/vlc_burn_subs_export.log
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
echo "$(date)" > /tmp/vlc_burn_subs_completed.txt
echo "Burn subtitles task export completed" >> /tmp/vlc_burn_subs_completed.txt

echo "=== Export Complete ==="