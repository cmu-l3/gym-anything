#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Crop Video Borders Result ==="

# Expected output location
EXPECTED_OUTPUT="/home/ga/Videos/dashcam_cropped.mp4"
EXPORT_LOCATION="/tmp/vlc_crop_borders_output.mp4"

# Check for cropped video at expected location
if [ -f "$EXPECTED_OUTPUT" ]; then
    echo "✅ Cropped video found at expected location: $EXPECTED_OUTPUT"
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$EXPECTED_OUTPUT" 2>/dev/null || stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    echo "   File size: $((FILE_SIZE / 1024)) KB"
    
    # Get video resolution
    RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$EXPECTED_OUTPUT" 2>/dev/null || echo "unknown")
    echo "   Resolution: $RESOLUTION"
    
    # Copy to export location
    cp "$EXPECTED_OUTPUT" "$EXPORT_LOCATION"
    echo "   Copied to: $EXPORT_LOCATION"
else
    echo "⚠️ Cropped video not found at expected location: $EXPECTED_OUTPUT"
    
    # Search for any recently created video files in Videos directory
    echo "Searching for recently created video files..."
    RECENT_VIDEOS=$(find /home/ga/Videos -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 2>/dev/null | grep -v "dashcam_raw.mp4" || true)
    
    if [ -n "$RECENT_VIDEOS" ]; then
        echo "Found recent video files:"
        echo "$RECENT_VIDEOS"
        
        # Use the most recent one
        MOST_RECENT=$(echo "$RECENT_VIDEOS" | head -1)
        echo "Using most recent: $MOST_RECENT"
        
        FILE_SIZE=$(stat -f%z "$MOST_RECENT" 2>/dev/null || stat -c%s "$MOST_RECENT" 2>/dev/null || echo "0")
        RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$MOST_RECENT" 2>/dev/null || echo "unknown")
        
        echo "   File size: $((FILE_SIZE / 1024)) KB"
        echo "   Resolution: $RESOLUTION"
        
        cp "$MOST_RECENT" "$EXPORT_LOCATION"
    else
        echo "❌ No recently created video files found"
    fi
fi

# Store metadata for verification
cat > /tmp/vlc_crop_borders_metadata.json <<EOF
{
    "expected_output": "$EXPECTED_OUTPUT",
    "output_exists": $([ -f "$EXPECTED_OUTPUT" ] && echo "true" || echo "false"),
    "export_location": "$EXPORT_LOCATION",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Metadata saved to /tmp/vlc_crop_borders_metadata.json"

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Kill any remaining VLC processes
kill_vlc ga || true

# Create completion marker
echo "$(date -Iseconds)" > /tmp/vlc_crop_borders_completed.txt
echo "Crop video borders task completed" >> /tmp/vlc_crop_borders_completed.txt
echo "Expected output: $EXPECTED_OUTPUT" >> /tmp/vlc_crop_borders_completed.txt
echo "File exists: $([ -f "$EXPECTED_OUTPUT" ] && echo 'yes' || echo 'no')" >> /tmp/vlc_crop_borders_completed.txt

echo "=== Export Complete ==="