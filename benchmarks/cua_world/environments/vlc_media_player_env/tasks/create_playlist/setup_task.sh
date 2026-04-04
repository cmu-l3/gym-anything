#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Playlist Task ==="

kill_vlc ga
sleep 1

# Ensure playlist directory exists
mkdir -p /home/ga/Videos/playlists
chown ga:ga /home/ga/Videos/playlists

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_playlist_task.log 2>&1 &"

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

echo "=== Create Playlist Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open playlist view (View -> Playlist or Ctrl+L)"
echo "  2. Add media files:"
echo "     - /home/ga/Videos/sample_video.mp4"
echo "     - /home/ga/Videos/color_test.mp4"
echo "     - /home/ga/Music/sample_audio.mp3"
echo "  3. Save playlist as: /home/ga/Videos/playlists/my_playlist.m3u"
echo "  4. Use Media -> Save Playlist to File"
