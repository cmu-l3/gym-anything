#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Load Subtitles Task ==="

kill_vlc ga
sleep 1

# Ensure subtitle file exists
SUBTITLE_FILE="/home/ga/Videos/subtitles/sample.srt"
if [ ! -f "$SUBTITLE_FILE" ]; then
    echo "ERROR: Subtitle file not found: $SUBTITLE_FILE"
    exit 1
fi

# Launch VLC with RC interface enabled and video (subtitle should be loaded manually)
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 /home/ga/Videos/sample_video.mp4 > /tmp/vlc_subtitle_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Load Subtitles Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing the sample video"
echo "  2. Load subtitle file: /home/ga/Videos/subtitles/sample.srt"
echo "  3. Use: Subtitle -> Add Subtitle File menu"
echo "  4. Navigate to /home/ga/Videos/subtitles/ and select sample.srt"
