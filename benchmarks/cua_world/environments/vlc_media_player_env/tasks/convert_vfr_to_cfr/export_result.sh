#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Convert VFR to CFR Result ==="

# Expected output file
CONVERTED_VIDEO="/home/ga/Videos/screen_recording_cfr.mp4"

# Check for converted video at expected location
if [ -f "$CONVERTED_VIDEO" ]; then
    echo "✅ Converted video found: $CONVERTED_VIDEO"
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$CONVERTED_VIDEO" 2>/dev/null || stat -c%s "$CONVERTED_VIDEO" 2>/dev/null || echo "0")
    FILE_SIZE_MB=$(echo "scale=1; $FILE_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "unknown")
    
    echo "File size: ${FILE_SIZE_MB} MB"
    
    # Show basic video info
    if command -v ffprobe &> /dev/null; then
        echo "Video properties:"
        ffprobe -v error -select_streams v:0 \
          -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,duration \
          -of default=noprint_wrappers=1 \
          "$CONVERTED_VIDEO" 2>/dev/null || echo "Could not analyze video"
    fi
    
    # Copy to /tmp for verification
    cp "$CONVERTED_VIDEO" /tmp/vlc_converted_cfr_video.mp4
    echo "✅ Copied to /tmp for verification"
    
else
    echo "⚠️ Converted video not found at expected location: $CONVERTED_VIDEO"
    
    # Look for any recently created MP4 in Videos directory
    echo "Searching for recent conversions..."
    RECENT_VIDEO=$(find /home/ga/Videos -name "*.mp4" -type f -mmin -10 2>/dev/null | grep -v "screen_recording_vfr" | head -1)
    
    if [ -n "$RECENT_VIDEO" ] && [ -f "$RECENT_VIDEO" ]; then
        echo "Found recent video: $RECENT_VIDEO"
        FILE_SIZE=$(stat -f%z "$RECENT_VIDEO" 2>/dev/null || stat -c%s "$RECENT_VIDEO" 2>/dev/null || echo "0")
        FILE_SIZE_MB=$(echo "scale=1; $FILE_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "unknown")
        echo "File size: ${FILE_SIZE_MB} MB"
        
        # Copy it as the result
        cp "$RECENT_VIDEO" /tmp/vlc_converted_cfr_video.mp4
        echo "✅ Using recent file for verification"
    else
        echo "❌ No suitable converted video found"
        # Create empty marker to indicate failure
        touch /tmp/vlc_convert_cfr_failed.txt
    fi
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
        sleep 1
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_convert_cfr_completed.txt
echo "VFR to CFR conversion task completed" >> /tmp/vlc_convert_cfr_completed.txt

# Save original video info for comparison
if [ -f /home/ga/Videos/screen_recording_vfr.mkv ] && command -v ffprobe &> /dev/null; then
    echo "Original VFR video info:" > /tmp/vlc_original_vfr_info.txt
    ffprobe -v error -select_streams v:0 \
      -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,duration \
      -show_entries format=duration \
      -of default=noprint_wrappers=1 \
      /home/ga/Videos/screen_recording_vfr.mkv 2>/dev/null >> /tmp/vlc_original_vfr_info.txt || true
fi

echo "=== Export Complete ==="