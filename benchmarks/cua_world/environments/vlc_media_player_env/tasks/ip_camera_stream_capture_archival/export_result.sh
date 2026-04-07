#!/bin/bash
echo "=== Exporting Task Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Gather Video Output
OUTPUT_FILE="/home/ga/Videos/camera_archive/cam01_capture.mp4"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
VIDEO_INFO="{}"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Use ffprobe to extract reliable codec/container details
    VIDEO_INFO=$(ffprobe -v error -show_format -show_streams -of json "$OUTPUT_FILE" 2>/dev/null)
    if [ -z "$VIDEO_INFO" ]; then
        VIDEO_INFO="{}"
    fi
    
    # Copy to /tmp to avoid permission issues for the verifier
    cp "$OUTPUT_FILE" /tmp/cam01_capture.mp4 2>/dev/null || true
fi

# 2. Gather Snapshots
mkdir -p /tmp/snapshots
find /home/ga/Pictures/vlc -maxdepth 1 -name "*.png" -mtime -1 -exec cp {} /tmp/snapshots/ \; 2>/dev/null || true
SNAPSHOT_COUNT=$(ls -1 /tmp/snapshots/*.png 2>/dev/null | wc -l)

# 3. Gather Report
REPORT_EXISTS="false"
if [ -f "/home/ga/Documents/stream_report.json" ]; then
    REPORT_EXISTS="true"
    cp "/home/ga/Documents/stream_report.json" /tmp/stream_report.json 2>/dev/null || true
fi

# 4. Write JSON Manifest
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "snapshot_count": $SNAPSHOT_COUNT,
    "report_exists": $REPORT_EXISTS,
    "video_info": $VIDEO_INFO
}
EOF

# Make result readable by verifier
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Cleanup background stream
pkill -f "cvlc.*/tmp/source_camera.ts" 2>/dev/null || true

echo "=== Export Complete ==="