#!/bin/bash
set -e
echo "=== Exporting Amalfi Coast Flythrough task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
scrot /tmp/task_evidence/final_state.png 2>/dev/null || \
    import -window root /tmp/task_evidence/final_state.png 2>/dev/null || true

# Check if output file exists and gather metadata
OUTPUT_PATH="/home/ga/Videos/amalfi_flythrough.mp4"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
VIDEO_WIDTH="0"
VIDEO_HEIGHT="0"
VIDEO_DURATION="0"
VIDEO_FORMAT="none"
VIDEO_CODEC="none"
VIDEO_FPS="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_PATH"
    echo "File size: $OUTPUT_SIZE bytes"
    echo "File mtime: $OUTPUT_MTIME"
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task (anti-gaming check passed)"
    else
        echo "WARNING: File predates task start time"
    fi
    
    # Get video metadata using ffprobe
    if command -v ffprobe &> /dev/null; then
        echo "Analyzing video with ffprobe..."
        
        # Get format info
        VIDEO_FORMAT=$(ffprobe -v quiet -show_entries format=format_name -of csv=p=0 "$OUTPUT_PATH" 2>/dev/null || echo "unknown")
        VIDEO_DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$OUTPUT_PATH" 2>/dev/null || echo "0")
        
        # Get video stream info
        VIDEO_WIDTH=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUTPUT_PATH" 2>/dev/null || echo "0")
        VIDEO_HEIGHT=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUTPUT_PATH" 2>/dev/null || echo "0")
        VIDEO_CODEC=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$OUTPUT_PATH" 2>/dev/null || echo "unknown")
        VIDEO_FPS=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$OUTPUT_PATH" 2>/dev/null || echo "0")
        
        echo "Video format: $VIDEO_FORMAT"
        echo "Video resolution: ${VIDEO_WIDTH}x${VIDEO_HEIGHT}"
        echo "Video duration: $VIDEO_DURATION seconds"
        echo "Video codec: $VIDEO_CODEC"
        echo "Video FPS: $VIDEO_FPS"
    else
        echo "WARNING: ffprobe not available for video analysis"
    fi
    
    # Extract sample frames for VLM analysis
    if command -v ffmpeg &> /dev/null; then
        echo "Extracting sample frames..."
        mkdir -p /tmp/task_evidence/frames
        
        # Extract start, middle, and end frames
        ffmpeg -y -ss 0 -i "$OUTPUT_PATH" -vframes 1 -f image2 /tmp/task_evidence/frames/frame_start.png 2>/dev/null || true
        
        # Calculate middle timestamp
        if [ -n "$VIDEO_DURATION" ] && [ "$VIDEO_DURATION" != "0" ]; then
            MIDDLE_TS=$(python3 -c "print(float('$VIDEO_DURATION') / 2)" 2>/dev/null || echo "5")
            ffmpeg -y -ss "$MIDDLE_TS" -i "$OUTPUT_PATH" -vframes 1 -f image2 /tmp/task_evidence/frames/frame_middle.png 2>/dev/null || true
        fi
        
        # Extract near-end frame
        if [ -n "$VIDEO_DURATION" ] && [ "$VIDEO_DURATION" != "0" ]; then
            END_TS=$(python3 -c "print(max(0, float('$VIDEO_DURATION') - 1))" 2>/dev/null || echo "10")
            ffmpeg -y -ss "$END_TS" -i "$OUTPUT_PATH" -vframes 1 -f image2 /tmp/task_evidence/frames/frame_end.png 2>/dev/null || true
        fi
        
        FRAME_COUNT=$(ls -1 /tmp/task_evidence/frames/*.png 2>/dev/null | wc -l || echo "0")
        echo "Extracted $FRAME_COUNT sample frames"
    fi
else
    echo "Output file NOT found at: $OUTPUT_PATH"
    
    # Check what files exist in the Videos directory
    echo "Contents of /home/ga/Videos/:"
    ls -la /home/ga/Videos/ 2>/dev/null || echo "Directory empty or not accessible"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi
echo "Google Earth running: $GE_RUNNING"

# Check for Google Earth windows
GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | wc -l || echo "0")
echo "Google Earth windows: $GE_WINDOWS"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "video_width": $VIDEO_WIDTH,
    "video_height": $VIDEO_HEIGHT,
    "video_duration": $VIDEO_DURATION,
    "video_format": "$VIDEO_FORMAT",
    "video_codec": "$VIDEO_CODEC",
    "video_fps": "$VIDEO_FPS",
    "google_earth_running": $GE_RUNNING,
    "google_earth_windows": $GE_WINDOWS,
    "frames_extracted": $(ls -1 /tmp/task_evidence/frames/*.png 2>/dev/null | wc -l || echo "0"),
    "final_screenshot": "/tmp/task_evidence/final_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json