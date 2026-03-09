#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Convert Video Task ==="

kill_vlc ga
sleep 1

# Ensure converted directory exists
mkdir -p /home/ga/Videos/converted
chown ga:ga /home/ga/Videos/converted

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_convert_task.log 2>&1 &"

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

echo "=== Convert Video Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Convert /home/ga/Videos/convert_source.mp4 to AVI format"
echo "  2. Use Media -> Convert/Save (Ctrl+R)"
echo "  3. Add source file: /home/ga/Videos/convert_source.mp4"
echo "  4. Click Convert/Save button"
echo "  5. Choose profile (e.g., Video - H.264 + MP3 (MP4))"
echo "  6. Set destination: /home/ga/Videos/converted/output.avi"
echo "  7. Start conversion"
