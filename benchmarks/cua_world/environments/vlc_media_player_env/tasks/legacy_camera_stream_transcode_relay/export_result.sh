#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Probe the RTSP Stream
echo "Probing RTSP stream..."
timeout 10 ffprobe -v error -show_entries stream=codec_name -of json rtsp://127.0.0.1:8554/cam1 > /tmp/rtsp_probe.json 2>/dev/null || echo "{}" > /tmp/rtsp_probe.json

# 2. Probe the Archive File
ARCHIVE_PATH="/home/ga/Videos/archive.mp4"
ARCHIVE_EXISTS="false"
ARCHIVE_MTIME=0
ARCHIVE_SIZE=0

echo "Probing Archive file..."
if [ -f "$ARCHIVE_PATH" ]; then
    ARCHIVE_EXISTS="true"
    ARCHIVE_MTIME=$(stat -c %Y "$ARCHIVE_PATH" 2>/dev/null || echo "0")
    ARCHIVE_SIZE=$(stat -c %s "$ARCHIVE_PATH" 2>/dev/null || echo "0")
    timeout 5 ffprobe -v error -show_entries stream=codec_name -of json "$ARCHIVE_PATH" > /tmp/file_probe.json 2>/dev/null || echo "{}" > /tmp/file_probe.json
else
    echo "{}" > /tmp/file_probe.json
fi

# 3. Process Anti-Gaming Checks
# Is VLC running with a stream output command?
VLC_RUNNING=$(pgrep -f "vlc.*sout" > /dev/null && echo "true" || echo "false")

# Did the agent cheat and use ffmpeg to serve the RTSP stream?
# We exclude our own legacy camera ffmpeg process.
AGENT_USED_FFMPEG=$(ps aux | grep ffmpeg | grep -v "sample_video.mp4" | grep -v grep > /dev/null && echo "true" || echo "false")

# 4. Script Check
SCRIPT_EXISTS=$([ -f /home/ga/start_relay.sh ] && echo "true" || echo "false")
SCRIPT_EXECUTABLE=$([ -x /home/ga/start_relay.sh ] && echo "true" || echo "false")

# Combine results into one JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "archive_exists": $ARCHIVE_EXISTS,
    "archive_mtime": $ARCHIVE_MTIME,
    "archive_size_bytes": $ARCHIVE_SIZE,
    "vlc_running": $VLC_RUNNING,
    "agent_used_ffmpeg": $AGENT_USED_FFMPEG,
    "script_exists": $SCRIPT_EXISTS,
    "script_executable": $SCRIPT_EXECUTABLE,
    "rtsp_probe": $(cat /tmp/rtsp_probe.json),
    "file_probe": $(cat /tmp/file_probe.json)
}
EOF

# Move securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="