#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Take Snapshot Task ==="

kill_vlc ga
sleep 1

# Launch VLC with video
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused /home/ga/Videos/color_test.mp4 > /tmp/vlc_snapshot_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Seek to 5 seconds
echo "Seeking to 5 seconds..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5
for i in {1..5}; do
    su - ga -c "DISPLAY=:1 xdotool key shift+Right" || true
    sleep 0.3
done
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Take Snapshot Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is paused at approximately 5 seconds"
echo "  2. Take a snapshot using Shift+S"
echo "  3. Snapshot will be saved to /home/ga/Pictures/vlc/"
