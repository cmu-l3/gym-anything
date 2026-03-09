#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Playback Issue Task ==="

kill_vlc ga
sleep 1

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any previous diagnostic reports
rm -f /home/ga/Documents/diagnostic_report.txt
rm -f /home/ga/Documents/*diagnostic*.txt

# Generate a problematic video file (video with NO audio track)
# This simulates a common user complaint: "there's no sound"
echo "Creating problematic video file (no audio track)..."

PROBLEM_VIDEO="/home/ga/Videos/problem_video.mkv"

# Create video-only file using ffmpeg
# Using testsrc pattern so it's clearly a test video with visible info
ffmpeg -f lavfi -i testsrc=duration=15:size=1280x720:rate=30 \
    -c:v libx264 -pix_fmt yuv420p -preset fast \
    "$PROBLEM_VIDEO" -y > /tmp/ffmpeg_create.log 2>&1

if [ ! -f "$PROBLEM_VIDEO" ]; then
    echo "ERROR: Failed to create problem video"
    cat /tmp/ffmpeg_create.log
    exit 1
fi

echo "✅ Problem video created: $PROBLEM_VIDEO"
ls -lh "$PROBLEM_VIDEO"

# Verify it has no audio using ffprobe
echo "Verifying problem video properties..."
ffprobe -v error -show_streams -of json "$PROBLEM_VIDEO" > /tmp/problem_video_info.json 2>&1
AUDIO_STREAMS=$(jq '[.streams[] | select(.codec_type=="audio")] | length' /tmp/problem_video_info.json 2>/dev/null || echo "0")
VIDEO_STREAMS=$(jq '[.streams[] | select(.codec_type=="video")] | length' /tmp/problem_video_info.json 2>/dev/null || echo "0")

echo "Video streams: $VIDEO_STREAMS, Audio streams: $AUDIO_STREAMS"

if [ "$AUDIO_STREAMS" != "0" ]; then
    echo "WARNING: Problem video has audio tracks (expected 0)"
fi

if [ "$VIDEO_STREAMS" = "0" ]; then
    echo "ERROR: Problem video has no video tracks"
    exit 1
fi

chown ga:ga "$PROBLEM_VIDEO"

# Launch VLC with the problem video and RC interface for potential querying
echo "Launching VLC with problem video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 '$PROBLEM_VIDEO' > /tmp/vlc_diagnose_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_diagnose_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Let video play briefly to ensure it's loaded
sleep 2

echo "=== Diagnose Playback Issue Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  Problem: Video file at /home/ga/Videos/problem_video.mkv has an issue"
echo "  Task: Diagnose the problem and create a technical report"
echo ""
echo "  Steps:"
echo "    1. Use Tools → Codec Information (Ctrl+J) to view technical details"
echo "    2. Use Tools → Messages (Ctrl+M, verbosity 2) to check for errors"
echo "    3. Document findings in /home/ga/Documents/diagnostic_report.txt"
echo ""
echo "  Report should include:"
echo "    - File name and path"
echo "    - Container format (e.g., Matroska/MKV)"
echo "    - Video codec, resolution, framerate"
echo "    - Audio codec and track count (note: this is the problem!)"
echo "    - Any error messages"
echo "    - Problem description (e.g., 'No audio track present')"
echo "    - Recommendation (e.g., 'Re-encode with audio' or 'Check source file')"
echo ""