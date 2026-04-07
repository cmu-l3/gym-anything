#!/bin/bash
echo "=== Exporting Planetarium Stereoscopic Formatting results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Prepare frames directory for SSIM evaluation
mkdir -p /tmp/frames
chmod 777 /tmp/frames

# Helper function to get metadata via ffprobe
probe_file() {
    local filepath=$1
    if [ -f "$filepath" ]; then
        # File exists
        local exists="true"
        local size=$(stat -c %s "$filepath")
        local mtime=$(stat -c %Y "$filepath")
        local created_during_task="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi
        
        # Resolution
        local resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$filepath" 2>/dev/null || echo "0x0")
        
        # Audio check
        local audio_streams=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of default=nw=1:nk=1 "$filepath" 2>/dev/null | wc -l)
        local has_audio="false"
        if [ "$audio_streams" -gt 0 ]; then
            has_audio="true"
        fi

        echo "{\"exists\": $exists, \"size\": $size, \"created_during_task\": $created_during_task, \"resolution\": \"$resolution\", \"has_audio\": $has_audio}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false, \"resolution\": \"0x0\", \"has_audio\": false}"
    fi
}

# 1. Probe agent outputs
LOBBY_INFO=$(probe_file "/home/ga/Videos/exhibits/lobby_2d.mp4")
DOME_INFO=$(probe_file "/home/ga/Videos/exhibits/dome_right.mp4")
ANAGLYPH_INFO=$(probe_file "/home/ga/Videos/exhibits/classroom_anaglyph.mp4")

# 2. Extract specific frames for structural similarity comparison (t=5s)
# Extract ground truth frames
ffmpeg -y -v error -i /var/lib/app/ground_truth/gt_lobby_2d.mp4 -ss 00:00:05 -vframes 1 /tmp/frames/gt_lobby.png
ffmpeg -y -v error -i /var/lib/app/ground_truth/gt_dome_right.mp4 -ss 00:00:05 -vframes 1 /tmp/frames/gt_dome.png
ffmpeg -y -v error -i /var/lib/app/ground_truth/gt_classroom_anaglyph.mp4 -ss 00:00:05 -vframes 1 /tmp/frames/gt_anaglyph.png

# Extract agent frames if files exist
if [ -f "/home/ga/Videos/exhibits/lobby_2d.mp4" ]; then
    ffmpeg -y -v error -i /home/ga/Videos/exhibits/lobby_2d.mp4 -ss 00:00:05 -vframes 1 /tmp/frames/agent_lobby.png 2>/dev/null || true
fi
if [ -f "/home/ga/Videos/exhibits/dome_right.mp4" ]; then
    ffmpeg -y -v error -i /home/ga/Videos/exhibits/dome_right.mp4 -ss 00:00:05 -vframes 1 /tmp/frames/agent_dome.png 2>/dev/null || true
fi
if [ -f "/home/ga/Videos/exhibits/classroom_anaglyph.mp4" ]; then
    ffmpeg -y -v error -i /home/ga/Videos/exhibits/classroom_anaglyph.mp4 -ss 00:00:05 -vframes 1 /tmp/frames/agent_anaglyph.png 2>/dev/null || true
fi

# 3. Compile report
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "outputs": {
        "lobby_2d": $LOBBY_INFO,
        "dome_right": $DOME_INFO,
        "classroom_anaglyph": $ANAGLYPH_INFO
    }
}
EOF

# Move results handling permissions securely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# Manifest will be copied natively by copy_from_env in the python verifier.

echo "Export complete. Results stored in /tmp/task_result.json and /tmp/frames/"