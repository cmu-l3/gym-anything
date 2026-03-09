#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Seek Timestamp Task ==="

kill_vlc ga
sleep 1

# Launch VLC with video (without --start-paused to allow video output initialization)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show /home/ga/Videos/sample_video.mp4 > /tmp/vlc_seek_task.log 2>&1 &"

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

# Let video play for 2 seconds to initialize video output (required for snapshots to work)
echo "Initializing video output..."
sleep 2

# Pause the video
echo "Pausing video..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

# Seek back to start
echo "Seeking to start..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 0.5

echo "=== Seek Timestamp Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is paused at the start of the video"
echo "  2. Seek to timestamp 00:15 (15 seconds)"
echo "  3. Methods:"
echo "     - Click on progress bar at 15s position"
echo "     - Use keyboard: Shift+Right to jump forward"
echo "     - Use Go -> Jump to Time menu"
echo "  4. Take a snapshot to verify position (Shift+S)"
