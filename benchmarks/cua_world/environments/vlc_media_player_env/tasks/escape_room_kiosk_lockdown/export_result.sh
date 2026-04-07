#!/bin/bash
echo "=== Exporting escape_room_kiosk_lockdown results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

KIOSK_VIDEO="/home/ga/Videos/kiosk_loop.mp4"
RAW_VIDEO="/home/ga/Videos/briefing_raw.mp4"
CONFIG_FILE="/home/ga/Documents/kiosk_vlcrc"
SCRIPT_FILE="/home/ga/Desktop/start_kiosk.sh"

# Extract properties
VIDEO_EXISTS="false"
WIDTH=0
HEIGHT=0
AUDIO_STREAMS=0
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
CONFIG_EXISTS="false"

if [ -f "$KIOSK_VIDEO" ]; then
    VIDEO_EXISTS="true"
    
    # Get properties using ffprobe
    WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of default=nw=1:nk=1 "$KIOSK_VIDEO" 2>/dev/null || echo "0")
    HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of default=nw=1:nk=1 "$KIOSK_VIDEO" 2>/dev/null || echo "0")
    AUDIO_STREAMS=$(ffprobe -v error -select_streams a -show_entries stream=index -of default=nw=1:nk=1 "$KIOSK_VIDEO" 2>/dev/null | wc -l || echo "0")
    
    # Trim whitespace just in case
    WIDTH=$(echo "$WIDTH" | tr -d '[:space:]')
    HEIGHT=$(echo "$HEIGHT" | tr -d '[:space:]')
    AUDIO_STREAMS=$(echo "$AUDIO_STREAMS" | tr -d '[:space:]')
    
    # Extract frames for visual comparison by verifier (at 5-second mark)
    ffmpeg -y -ss 00:00:05 -i "$RAW_VIDEO" -vframes 1 /tmp/frame_raw.png 2>/dev/null || true
    ffmpeg -y -ss 00:00:05 -i "$KIOSK_VIDEO" -vframes 1 /tmp/frame_kiosk.png 2>/dev/null || true
fi

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    cp "$CONFIG_FILE" /tmp/kiosk_vlcrc 2>/dev/null || sudo cp "$CONFIG_FILE" /tmp/kiosk_vlcrc
    chmod 666 /tmp/kiosk_vlcrc 2>/dev/null || sudo chmod 666 /tmp/kiosk_vlcrc 2>/dev/null || true
fi

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    cp "$SCRIPT_FILE" /tmp/start_kiosk.sh 2>/dev/null || sudo cp "$SCRIPT_FILE" /tmp/start_kiosk.sh
    chmod 666 /tmp/start_kiosk.sh 2>/dev/null || sudo chmod 666 /tmp/start_kiosk.sh 2>/dev/null || true
    
    if [ -x "$SCRIPT_FILE" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
fi

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "video_exists": $VIDEO_EXISTS,
    "width": ${WIDTH:-0},
    "height": ${HEIGHT:-0},
    "audio_streams": ${AUDIO_STREAMS:-0},
    "config_exists": $CONFIG_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "script_executable": $SCRIPT_EXECUTABLE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="