#!/bin/bash
# Export script for retail_video_wall_vlm_orchestration task
set -e

echo "=== Exporting retail_video_wall_vlm_orchestration results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check running processes
VLC_PID=$(pgrep -f "vlc" | head -n 1)
VLC_RUNNING="false"
if [ -n "$VLC_PID" ]; then
    VLC_RUNNING="true"
fi

FFMPEG_RUNNING="false"
if pgrep -f "ffmpeg" > /dev/null; then
    FFMPEG_RUNNING="true"
fi

# Copy artifacts
VLM_FILE_EXISTS="false"
VLM_CONTENT=""
if [ -f "/home/ga/Documents/signage.vlm" ]; then
    VLM_FILE_EXISTS="true"
    cp "/home/ga/Documents/signage.vlm" "/tmp/signage.vlm"
    VLM_CONTENT=$(cat "/home/ga/Documents/signage.vlm" | base64 -w 0)
fi

SCRIPT_EXISTS="false"
if [ -f "/home/ga/start_signage.sh" ]; then
    SCRIPT_EXISTS="true"
    cp "/home/ga/start_signage.sh" "/tmp/start_signage.sh"
fi

# Function to probe a network stream
probe_stream() {
    local url=$1
    local output_file=$2
    
    echo "Probing $url ..."
    # We use a short timeout and analyze the stream
    timeout 5 ffprobe -v error -show_entries stream=codec_type,codec_name -of json "$url" > "$output_file" 2>/dev/null || true
    
    # If ffprobe failed to get json, initialize with empty structure
    if [ ! -s "$output_file" ]; then
        echo '{"streams": []}' > "$output_file"
    fi
}

# Probe the 3 expected HTTP streams
probe_stream "http://127.0.0.1:8081/window" "/tmp/probe_window.json"
probe_stream "http://127.0.0.1:8082/entrance" "/tmp/probe_entrance.json"
probe_stream "http://127.0.0.1:8083/checkout" "/tmp/probe_checkout.json"

# Collect stream data into a single JSON
WINDOW_PROBE=$(cat /tmp/probe_window.json)
ENTRANCE_PROBE=$(cat /tmp/probe_entrance.json)
CHECKOUT_PROBE=$(cat /tmp/probe_checkout.json)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/vlm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "vlc_running": $VLC_RUNNING,
    "ffmpeg_running": $FFMPEG_RUNNING,
    "vlm_file_exists": $VLM_FILE_EXISTS,
    "vlm_content_b64": "$VLM_CONTENT",
    "script_exists": $SCRIPT_EXISTS,
    "streams": {
        "window": $WINDOW_PROBE,
        "entrance": $ENTRANCE_PROBE,
        "checkout": $CHECKOUT_PROBE
    }
}
EOF

# Move to final location
rm -f /tmp/vlm_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/vlm_task_result.json
chmod 666 /tmp/vlm_task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/vlm_task_result.json"
echo "=== Export complete ==="