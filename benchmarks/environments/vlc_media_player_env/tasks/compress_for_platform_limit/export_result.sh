#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compress for Platform Limit Result ==="

OUTPUT_VIDEO="/home/ga/Videos/compressed/birthday_email.mp4"
OUTPUT_DIR="/home/ga/Videos/compressed"

# Check for output file at expected location
if [ -f "$OUTPUT_VIDEO" ]; then
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_VIDEO" 2>/dev/null || stat -f%z "$OUTPUT_VIDEO" 2>/dev/null)
    OUTPUT_SIZE_MB=$(echo "scale=2; $OUTPUT_SIZE/1024/1024" | bc)
    echo "✅ Output file found: $OUTPUT_VIDEO"
    echo "   File size: ${OUTPUT_SIZE_MB}MB"
    
    # Copy to /tmp for verification
    cp "$OUTPUT_VIDEO" /tmp/vlc_compressed_output.mp4
    echo "   Copied to /tmp/vlc_compressed_output.mp4"
else
    echo "⚠️ Output file not found at expected location: $OUTPUT_VIDEO"
    
    # Look for any recently created video files in output directory
    echo "Searching for recent video files in $OUTPUT_DIR..."
    RECENT_VIDEO=$(find "$OUTPUT_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -15 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        RECENT_SIZE=$(stat -c%s "$RECENT_VIDEO" 2>/dev/null || stat -f%z "$RECENT_VIDEO" 2>/dev/null)
        RECENT_SIZE_MB=$(echo "scale=2; $RECENT_SIZE/1024/1024" | bc)
        echo "   File size: ${RECENT_SIZE_MB}MB"
        cp "$RECENT_VIDEO" /tmp/vlc_compressed_output.mp4
        echo "   Copied to /tmp/vlc_compressed_output.mp4"
    else
        echo "❌ No recent video files found in output directory"
        echo "   Conversion may not have completed successfully"
    fi
fi

# Check VLC log for conversion errors
if [ -f /tmp/vlc_compress_task.log ]; then
    echo ""
    echo "Checking VLC log for errors..."
    if grep -qi "error\|failed\|cannot" /tmp/vlc_compress_task.log; then
        echo "⚠️ Potential errors found in VLC log:"
        grep -i "error\|failed\|cannot" /tmp/vlc_compress_task.log | tail -5
    else
        echo "✅ No obvious errors in VLC log"
    fi
fi

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
        echo "VLC still running, force closing..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_compress_completed.txt
echo "Compression task export completed" >> /tmp/vlc_compress_completed.txt
if [ -f "$OUTPUT_VIDEO" ]; then
    echo "Output file: $OUTPUT_VIDEO" >> /tmp/vlc_compress_completed.txt
    echo "Output size: ${OUTPUT_SIZE_MB}MB" >> /tmp/vlc_compress_completed.txt
fi

echo ""
echo "=== Export Complete ==="