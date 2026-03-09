#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Mix Reference Task ==="

kill_vlc ga
sleep 1

# Ensure Music directory and playlists subdirectory exist
mkdir -p /home/ga/Music
mkdir -p /home/ga/Music/playlists
chown -R ga:ga /home/ga/Music

# Generate sample mix audio (30 seconds, 440Hz tone with slight variations)
# This represents the "user's mix" - slightly quieter and with less bass
echo "Generating sample mix audio..."
ffmpeg -f lavfi -i "sine=frequency=440:duration=30" \
    -f lavfi -i "sine=frequency=220:duration=30" \
    -filter_complex "[0]volume=0.6[a];[1]volume=0.3[b];[a][b]amix=inputs=2:duration=longest" \
    -codec:a libmp3lame -b:a 192k \
    /home/ga/Music/my_mix.mp3 -y 2>/dev/null

if [ ! -f /home/ga/Music/my_mix.mp3 ] || [ ! -s /home/ga/Music/my_mix.mp3 ]; then
    echo "ERROR: Failed to generate my_mix.mp3"
    exit 1
fi

echo "✅ Generated my_mix.mp3 ($(du -h /home/ga/Music/my_mix.mp3 | cut -f1))"

# Generate reference track audio (30 seconds, same frequency but louder and richer)
# This represents the "professional reference" - louder with more presence
echo "Generating reference track audio..."
ffmpeg -f lavfi -i "sine=frequency=440:duration=30" \
    -f lavfi -i "sine=frequency=220:duration=30" \
    -f lavfi -i "sine=frequency=880:duration=30" \
    -filter_complex "[0]volume=0.8[a];[1]volume=0.5[b];[2]volume=0.4[c];[a][b][c]amix=inputs=3:duration=longest" \
    -codec:a libmp3lame -b:a 192k \
    /home/ga/Music/reference_track.mp3 -y 2>/dev/null

if [ ! -f /home/ga/Music/reference_track.mp3 ] || [ ! -s /home/ga/Music/reference_track.mp3 ]; then
    echo "ERROR: Failed to generate reference_track.mp3"
    exit 1
fi

echo "✅ Generated reference_track.mp3 ($(du -h /home/ga/Music/reference_track.mp3 | cut -f1))"

# Set ownership
chown -R ga:ga /home/ga/Music

# Launch VLC with empty interface (agent will add files to playlist)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_mix_compare_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_mix_compare_task.log
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

echo "=== Compare Mix Reference Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open playlist view (View → Playlist or Ctrl+L)"
echo "  2. Add the following files to playlist IN ORDER:"
echo "     a. /home/ga/Music/my_mix.mp3 (your mix)"
echo "     b. /home/ga/Music/reference_track.mp3 (professional reference)"
echo "  3. Save playlist as XSPF:"
echo "     - Media → Save Playlist to File"
echo "     - Navigate to /home/ga/Music/playlists/"
echo "     - Filename: mix_comparison.xspf"
echo "     - Format: XSPF playlist"
echo ""
echo "💡 Tip: Order matters! Mix first, then reference for A/B comparison"