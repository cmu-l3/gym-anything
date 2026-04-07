#!/bin/bash
echo "=== Exporting result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Videos/localized_delivery/compliance_french_final.mp4"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
VIDEO_STREAMS=0
AUDIO_STREAMS=0
SUBTITLE_STREAMS=0

# Take final screenshot BEFORE any checks
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    echo "Probing streams in output video..."
    ffprobe -v error -show_streams -of json "$OUTPUT_PATH" > /tmp/output_probe.json 2>/dev/null
    
    # Use grep to count stream types if jq is unavailable
    VIDEO_STREAMS=$(grep -c '"codec_type": "video"' /tmp/output_probe.json || echo "0")
    AUDIO_STREAMS=$(grep -c '"codec_type": "audio"' /tmp/output_probe.json || echo "0")
    SUBTITLE_STREAMS=$(grep -c '"codec_type": "subtitle"' /tmp/output_probe.json || echo "0")

    # Extract a frame at the 15-second mark for VLM visual verification
    # (Checking for hardsubbed text and watermark)
    echo "Extracting frame at 00:00:15..."
    ffmpeg -y -ss 00:00:15 -i "$OUTPUT_PATH" -vframes 1 /tmp/frame_15s.png 2>/dev/null
else
    echo "{}" > /tmp/output_probe.json
fi

# Create JSON result
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "video_streams": $VIDEO_STREAMS,
    "audio_streams": $AUDIO_STREAMS,
    "subtitle_streams": $SUBTITLE_STREAMS
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/output_probe.json /tmp/frame_15s.png /tmp/task_final.png 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="