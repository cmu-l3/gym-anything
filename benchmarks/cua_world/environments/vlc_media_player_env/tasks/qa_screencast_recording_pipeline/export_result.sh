#!/bin/bash
echo "=== Exporting QA Screencast Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
VIDEO_PATH="/home/ga/Videos/qa_reports/jira_attachment_bug_1044.mp4"

# Check if file exists and get stats
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
CODEC_NAME=""
FPS="0"

if [ -f "$VIDEO_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$VIDEO_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$VIDEO_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Extract video info using ffprobe
    PROBE_DATA=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name,r_frame_rate -of json "$VIDEO_PATH" 2>/dev/null)
    if [ -n "$PROBE_DATA" ]; then
        CODEC_NAME=$(echo "$PROBE_DATA" | grep -o '"codec_name": "[^"]*' | cut -d'"' -f4 || echo "")
        
        # Calculate FPS from fraction (e.g., "10/1")
        FPS_FRACTION=$(echo "$PROBE_DATA" | grep -o '"r_frame_rate": "[^"]*' | cut -d'"' -f4 || echo "0/1")
        if [[ "$FPS_FRACTION" == *"/"* ]]; then
            NUM=$(echo "$FPS_FRACTION" | cut -d'/' -f1)
            DEN=$(echo "$FPS_FRACTION" | cut -d'/' -f2)
            if [ "$DEN" -ne "0" ]; then
                FPS=$(awk "BEGIN {printf \"%.2f\", $NUM/$DEN}")
            fi
        fi
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/qa_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "video_codec": "$CODEC_NAME",
    "fps": $FPS
}
EOF

# Move JSON out safely
rm -f /tmp/qa_screencast_result.json 2>/dev/null || sudo rm -f /tmp/qa_screencast_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/qa_screencast_result.json
chmod 666 /tmp/qa_screencast_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/qa_screencast_result.json

echo "=== Export complete ==="