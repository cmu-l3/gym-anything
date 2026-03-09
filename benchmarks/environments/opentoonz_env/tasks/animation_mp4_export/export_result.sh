#!/bin/bash
echo "=== Exporting animation_mp4_export result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/video_export"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Search for video files in output dir
VIDEO_FILE=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.mp4" -o -name "*.mov" \
    -o -name "*.avi" -o -name "*.webm" -o -name "*.mkv" -o -name "*.flv" \) \
    -type f 2>/dev/null | sort | head -1)

VIDEO_FOUND="false"
VIDEO_PATH=""
VIDEO_SIZE_KB=0
VIDEO_EXTENSION=""
VIDEO_NEWER_THAN_START="false"
VIDEO_DURATION_SEC=0
FFPROBE_VALID="false"

if [ -n "$VIDEO_FILE" ]; then
    VIDEO_FOUND="true"
    VIDEO_PATH="$VIDEO_FILE"
    VIDEO_SIZE_KB=$(du -sk "$VIDEO_FILE" 2>/dev/null | awk '{print $1}')
    VIDEO_SIZE_KB=${VIDEO_SIZE_KB:-0}
    VIDEO_EXTENSION="${VIDEO_FILE##*.}"

    # Check if created after task start
    if [ -f /tmp/task_start_timestamp ]; then
        NEWER=$(find "$OUTPUT_DIR" -maxdepth 3 -name "$(basename "$VIDEO_FILE")" \
            -newer /tmp/task_start_timestamp 2>/dev/null | wc -l)
        if [ "$NEWER" -gt 0 ]; then
            VIDEO_NEWER_THAN_START="true"
        fi
    fi

    # Use ffprobe to validate video and get duration
    if command -v ffprobe &>/dev/null; then
        FFPROBE_OUTPUT=$(ffprobe -v quiet -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$VIDEO_FILE" 2>/dev/null)
        if [ -n "$FFPROBE_OUTPUT" ] && echo "$FFPROBE_OUTPUT" | grep -qE '^[0-9]+\.?[0-9]*$'; then
            FFPROBE_VALID="true"
            VIDEO_DURATION_SEC=$(echo "$FFPROBE_OUTPUT" | awk '{printf "%d", $1}')
        fi
    fi
fi

# Count total video files found
VIDEO_COUNT=$(find "$OUTPUT_DIR" -maxdepth 3 \( -name "*.mp4" -o -name "*.mov" \
    -o -name "*.avi" -o -name "*.webm" -o -name "*.mkv" \) -type f 2>/dev/null | wc -l)
VIDEO_COUNT=${VIDEO_COUNT:-0}

INITIAL_COUNT=$(cat /tmp/mp4_export_initial_count 2>/dev/null || echo "0")

# Write result JSON (escape path safely)
VIDEO_PATH_SAFE=$(echo "$VIDEO_PATH" | sed 's/"/\\"/g')
RESULT_FILE="/tmp/mp4_export_result.json"
cat > "$RESULT_FILE" << RESULTEOF
{
    "video_found": $VIDEO_FOUND,
    "video_path": "$VIDEO_PATH_SAFE",
    "video_extension": "$VIDEO_EXTENSION",
    "video_size_kb": $VIDEO_SIZE_KB,
    "video_newer_than_start": $VIDEO_NEWER_THAN_START,
    "ffprobe_valid": $FFPROBE_VALID,
    "video_duration_sec": $VIDEO_DURATION_SEC,
    "video_count": $VIDEO_COUNT,
    "initial_count": $INITIAL_COUNT,
    "task_start": $TASK_START
}
RESULTEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "Result written to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="
