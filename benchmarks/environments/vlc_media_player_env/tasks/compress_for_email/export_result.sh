#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compress for Email Result ==="

# Expected output location
EXPECTED_OUTPUT="/home/ga/Videos/compressed/email_compressed.mp4"
EXPORT_LOCATION="/tmp/vlc_compressed_email.mp4"

# Check for compressed video at expected location
if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "✅ Compressed video found at expected location"
    FILE_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || stat -f%z "$EXPECTED_OUTPUT")
    FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
    echo "   Size: ${FILE_SIZE_MB}MB"
    
    cp "$EXPECTED_OUTPUT" "$EXPORT_LOCATION"
    
    # Check if size is under limit
    SIZE_LIMIT_BYTES=26214400  # 25MB
    if [ "$FILE_SIZE" -le "$SIZE_LIMIT_BYTES" ]; then
        echo "   ✅ Size is under 25MB limit"
    else
        echo "   ⚠️ Size exceeds 25MB limit"
    fi
else
    echo "⚠️ Compressed video not found at expected location: $EXPECTED_OUTPUT"
    
    # Look for any recently created video files in compressed directory
    COMPRESSED_DIR="/home/ga/Videos/compressed"
    if [ -d "$COMPRESSED_DIR" ]; then
        RECENT_VIDEO=$(find "$COMPRESSED_DIR" -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_VIDEO" ]; then
            echo "Found recent video: $RECENT_VIDEO"
            FILE_SIZE=$(stat -c%s "$RECENT_VIDEO" 2>/dev/null || stat -f%z "$RECENT_VIDEO")
            FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
            echo "   Size: ${FILE_SIZE_MB}MB"
            
            cp "$RECENT_VIDEO" "$EXPORT_LOCATION"
        else
            echo "No recent video files found in compressed directory"
        fi
    fi
fi

# Copy original video info for verification
if [ -f /tmp/email_source_info.json ]; then
    cp /tmp/email_source_info.json /tmp/vlc_original_info.json
fi

if [ -f /tmp/email_source_summary.txt ]; then
    cp /tmp/email_source_summary.txt /tmp/vlc_source_summary.txt
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

# Create completion marker
echo "$(date)" > /tmp/vlc_compress_completed.txt
echo "Compress for email task completed" >> /tmp/vlc_compress_completed.txt

if [ -f "$EXPORT_LOCATION" ]; then
    FINAL_SIZE=$(stat -c%s "$EXPORT_LOCATION" 2>/dev/null || stat -f%z "$EXPORT_LOCATION")
    FINAL_SIZE_MB=$(echo "scale=2; $FINAL_SIZE / 1048576" | bc)
    echo "Final compressed file size: ${FINAL_SIZE_MB}MB" >> /tmp/vlc_compress_completed.txt
fi

echo "=== Export Complete ==="