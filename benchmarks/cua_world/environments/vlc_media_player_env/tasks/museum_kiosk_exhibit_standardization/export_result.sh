#!/bin/bash
# Export script for museum_kiosk_exhibit_standardization task
set -e

echo "=== Exporting Museum Kiosk Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check script execution and contents
SCRIPT_PATH="/home/ga/Desktop/start_kiosk.sh"
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT=""

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ -x "$SCRIPT_PATH" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
    # Safely escape script content for JSON
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" | tr -d '\000-\011\013-\037' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
fi

# Probe video files
declare -A PROBE_RESULTS
for i in {1..3}; do
    FILE="/home/ga/Videos/kiosk_ready/exhibit_0${i}.mp4"
    if [ -f "$FILE" ]; then
        # Use ffprobe to get JSON metadata
        INFO=$(ffprobe -v quiet -print_format json -show_format -show_streams "$FILE" || echo "{}")
        # Extract mtime to verify it was created during task
        MTIME=$(stat -c %Y "$FILE" 2>/dev/null || echo "0")
        PROBE_RESULTS[$i]="{\"exists\": true, \"mtime\": $MTIME, \"ffprobe\": $INFO}"
    else
        PROBE_RESULTS[$i]="{\"exists\": false}"
    fi
done

# Extract a frame from exhibit_01 to check watermark
FRAME_EXTRACTED="false"
if [ -f "/home/ga/Videos/kiosk_ready/exhibit_01.mp4" ]; then
    # Extract frame at 1 second mark
    ffmpeg -y -i "/home/ga/Videos/kiosk_ready/exhibit_01.mp4" -ss 00:00:01 -vframes 1 /tmp/watermark_frame.png 2>/dev/null
    if [ -f "/tmp/watermark_frame.png" ]; then
        FRAME_EXTRACTED="true"
    fi
fi

# Check Playlist
PLAYLIST_PATH="/home/ga/Videos/kiosk_ready/ocean_loop.xspf"
PLAYLIST_EXISTS="false"
PLAYLIST_CONTENT=""
if [ -f "$PLAYLIST_PATH" ]; then
    PLAYLIST_EXISTS="true"
    PLAYLIST_CONTENT=$(cat "$PLAYLIST_PATH" | tr -d '\000-\011\013-\037' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
fi

# Get start time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Compile results into JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "script": {
        "exists": $SCRIPT_EXISTS,
        "executable": $SCRIPT_EXECUTABLE,
        "content": "$SCRIPT_CONTENT"
    },
    "playlist": {
        "exists": $PLAYLIST_EXISTS,
        "content": "$PLAYLIST_CONTENT"
    },
    "videos": {
        "1": ${PROBE_RESULTS[1]},
        "2": ${PROBE_RESULTS[2]},
        "3": ${PROBE_RESULTS[3]}
    },
    "frame_extracted": $FRAME_EXTRACTED
}
EOF

# Copy out to host accessible location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Make sure logo and frame are accessible to verifier
cp /home/ga/Pictures/museum_logo.png /tmp/museum_logo.png 2>/dev/null || true
chmod 666 /tmp/museum_logo.png 2>/dev/null || true
chmod 666 /tmp/watermark_frame.png 2>/dev/null || true

echo "=== Export Complete ==="