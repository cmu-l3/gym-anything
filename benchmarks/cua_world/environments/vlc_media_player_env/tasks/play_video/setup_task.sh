#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Play Video Task ==="

# Kill any existing VLC instances
kill_vlc ga

# Wait a moment
sleep 1

# Launch VLC with sample video
echo "Launching VLC with sample video..."
VIDEO_FILE="/home/ga/Videos/sample_video.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Sample video not found: $VIDEO_FILE"
    exit 1
fi

# Start VLC with the video, with hardware acceleration disabled
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --play-and-exit '$VIDEO_FILE' > /tmp/vlc_play_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_play_task.log
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
echo "Focusing VLC window..."
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Play Video Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC should now be playing the sample video"
echo "  2. Let the video play to completion (30 seconds)"
echo "  3. VLC will automatically stop when video ends"
echo ""
echo "  Alternative: Agent can press Space to pause/play if needed"
