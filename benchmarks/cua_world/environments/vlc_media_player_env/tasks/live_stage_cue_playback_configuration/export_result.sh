#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Initialize export values
PLAYLIST_EXISTS="false"
PLAYLIST_MTIME=0
VLCRC_EXISTS="false"
VLCRC_MTIME=0

# Check Playlist
PLAYLIST_PATH="/home/ga/Documents/show_cues.xspf"
if [ -f "$PLAYLIST_PATH" ]; then
    PLAYLIST_EXISTS="true"
    PLAYLIST_MTIME=$(stat -c %Y "$PLAYLIST_PATH" 2>/dev/null || echo "0")
    cp "$PLAYLIST_PATH" /tmp/show_cues_export.xspf
    chmod 666 /tmp/show_cues_export.xspf
fi

# Check vlcrc
VLCRC_PATH="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLCRC_PATH" ]; then
    VLCRC_EXISTS="true"
    VLCRC_MTIME=$(stat -c %Y "$VLCRC_PATH" 2>/dev/null || echo "0")
    cp "$VLCRC_PATH" /tmp/vlcrc_export
    chmod 666 /tmp/vlcrc_export
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "playlist_exists": $PLAYLIST_EXISTS,
    "playlist_mtime": $PLAYLIST_MTIME,
    "vlcrc_exists": $VLCRC_EXISTS,
    "vlcrc_mtime": $VLCRC_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="