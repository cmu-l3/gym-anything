#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Time-lapse Result ==="

# Expected output location
OUTPUT_VIDEO="/home/ga/Videos/timelapse_output.mp4"
SOURCE_VIDEO="/home/ga/Videos/painting_session.mp4"

# Check if output video exists
if [ -f "$OUTPUT_VIDEO" ]; then
    echo "✅ Time-lapse video found: $OUTPUT_VIDEO"
    
    # Get file size
    OUTPUT_SIZE=$(du -h "$OUTPUT_VIDEO" | cut -f1)
    echo "   File size: $OUTPUT_SIZE"
    
    # Copy output to /tmp for verification
    cp "$OUTPUT_VIDEO" /tmp/vlc_timelapse_output.mp4
    
    # Get detailed video info using ffprobe and save as JSON
    echo "Analyzing output video properties..."
    ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height,r_frame_rate,nb_frames \
      -of json "$OUTPUT_VIDEO" > /tmp/vlc_timelapse_output_info.json 2>&1 || echo '{"error": "ffprobe_failed"}' > /tmp/vlc_timelapse_output_info.json
    
    # Also get simple duration
    OUTPUT_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_VIDEO" 2>/dev/null || echo "0")
    echo "   Output duration: ${OUTPUT_DURATION}s"
    
else
    echo "⚠️ Time-lapse video not found at: $OUTPUT_VIDEO"
    
    # Search for any recently created video files in Videos directory
    echo "Searching for recently created video files..."
    RECENT_VIDEO=$(find /home/ga/Videos -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.mkv" \) -mmin -10 ! -name "painting_session.mp4" 2>/dev/null | head -1)
    
    if [ -n "$RECENT_VIDEO" ]; then
        echo "Found recent video file: $RECENT_VIDEO"
        cp "$RECENT_VIDEO" /tmp/vlc_timelapse_output.mp4
        
        # Get video info
        ffprobe -v error -show_entries format=duration,size -show_entries stream=codec_name,width,height,r_frame_rate \
          -of json "$RECENT_VIDEO" > /tmp/vlc_timelapse_output_info.json 2>&1 || echo '{"error": "ffprobe_failed"}' > /tmp/vlc_timelapse_output_info.json
    else
        echo "No recent video files found"
        echo '{"error": "output_not_found"}' > /tmp/vlc_timelapse_output_info.json
    fi
fi

# Also copy source video info for verification comparison
if [ -f "$SOURCE_VIDEO" ]; then
    SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null || echo "0")
    
    cat > /tmp/vlc_timelapse_source_info.json <<EOF
{
  "source_path": "$SOURCE_VIDEO",
  "source_duration": $SOURCE_DURATION,
  "expected_output_duration": $(echo "scale=2; $SOURCE_DURATION / 60.0" | bc),
  "expected_speedup": 60.0
}
EOF
else
    echo '{"error": "source_not_found"}' > /tmp/vlc_timelapse_source_info.json
fi

# Close VLC if running
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
echo "$(date)" > /tmp/vlc_timelapse_completed.txt
echo "Create time-lapse task completed" >> /tmp/vlc_timelapse_completed.txt

# Create summary
cat > /tmp/vlc_timelapse_summary.txt <<EOF
Create Time-lapse Task - Export Summary
========================================
Date: $(date)
Source: $SOURCE_VIDEO
Output: $OUTPUT_VIDEO
Output exists: $([ -f "$OUTPUT_VIDEO" ] && echo "YES" || echo "NO")
Output size: $([ -f "$OUTPUT_VIDEO" ] && du -h "$OUTPUT_VIDEO" | cut -f1 || echo "N/A")
EOF

cat /tmp/vlc_timelapse_summary.txt

echo "=== Export Complete ==="
ls -lh /tmp/vlc_timelapse_* 2>/dev/null || true