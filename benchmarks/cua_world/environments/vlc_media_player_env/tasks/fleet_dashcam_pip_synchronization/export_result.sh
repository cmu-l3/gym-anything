#!/bin/bash
echo "=== Exporting Fleet Dashcam PiP Synchronization Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Videos/incident_composite.mp4"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
DURATION="0"
WIDTH="0"
HEIGHT="0"
AUDIO_STREAMS="0"
VIDEO_STREAMS="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Get media info
    INFO=$(ffprobe -v error -show_entries format=duration -show_entries stream=width,height,codec_type -of json "$OUTPUT_PATH" 2>/dev/null)
    
    DURATION=$(echo "$INFO" | grep -o '"duration": "[^"]*"' | cut -d'"' -f4 | head -1 || echo "0")
    WIDTH=$(echo "$INFO" | grep -o '"width": [0-9]*' | cut -d' ' -f2 | head -1 || echo "0")
    HEIGHT=$(echo "$INFO" | grep -o '"height": [0-9]*' | cut -d' ' -f2 | head -1 || echo "0")
    AUDIO_STREAMS=$(echo "$INFO" | grep -c '"codec_type": "audio"' || echo "0")
    VIDEO_STREAMS=$(echo "$INFO" | grep -c '"codec_type": "video"' || echo "0")

    # Extract frames for verifier analysis
    # Frame at t=4.0 (Before flash)
    ffmpeg -y -ss 4.0 -i "$OUTPUT_PATH" -vframes 1 -q:v 2 /tmp/frame_4_0.png 2>/dev/null || true
    # Frame at t=5.1 (During flash, assuming properly synced and trimmed)
    ffmpeg -y -ss 5.1 -i "$OUTPUT_PATH" -vframes 1 -q:v 2 /tmp/frame_5_1.png 2>/dev/null || true
    # Frame at t=10.0 (After flash)
    ffmpeg -y -ss 10.0 -i "$OUTPUT_PATH" -vframes 1 -q:v 2 /tmp/frame_10_0.png 2>/dev/null || true
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "duration": "$DURATION",
    "width": "$WIDTH",
    "height": "$HEIGHT",
    "audio_streams": "$AUDIO_STREAMS",
    "video_streams": "$VIDEO_STREAMS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="