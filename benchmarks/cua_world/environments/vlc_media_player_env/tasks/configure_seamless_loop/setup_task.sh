#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Seamless Loop Task ==="

TASK_NAME="configure_seamless_loop"
USER_HOME="/home/ga"
VIDEOS_DIR="${USER_HOME}/Videos"
PLAYLISTS_DIR="${VIDEOS_DIR}/playlists"
TEMP_LOG="/tmp/${TASK_NAME}_setup.log"

# Kill any existing VLC instances
kill_vlc ga
sleep 1

echo "[$(date)] Setting up task: ${TASK_NAME}" | tee "${TEMP_LOG}"

# Create necessary directories
mkdir -p "${PLAYLISTS_DIR}"
mkdir -p "${USER_HOME}/.config/vlc"
mkdir -p "${USER_HOME}/.local/share/vlc"

# Clean any previous loop configurations and playlist
rm -f "${PLAYLISTS_DIR}/stream_loop.m3u"
rm -f "${USER_HOME}/.config/vlc/vlc-qt-interface.conf"

# Reset loop/repeat settings in vlcrc to default (disabled)
VLC_RC="${USER_HOME}/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^loop=/d' "$VLC_RC"
    sed -i '/^repeat=/d' "$VLC_RC"
    echo "Cleared previous loop/repeat settings"
fi

# Generate a 45-second test video with fade-to-black ending
# This simulates a real-world non-looping video
VIDEO_FILE="${VIDEOS_DIR}/stream_background.mp4"

echo "[$(date)] Generating test video with fade ending..." | tee -a "${TEMP_LOG}"

# Create a video with colorful test pattern and fade to black at the end
# This makes it obvious when the loop restarts if not configured properly
ffmpeg -f lavfi -i testsrc=duration=45:size=1280x720:rate=30 \
  -f lavfi -i sine=frequency=440:duration=45 \
  -vf "drawtext=text='Stream Background - Loop Me':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5,fade=t=out:st=42:d=3" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest \
  "${VIDEO_FILE}" -y 2>&1 | tee -a "${TEMP_LOG}"

if [ ! -f "${VIDEO_FILE}" ]; then
    echo "[ERROR] Failed to generate test video" | tee -a "${TEMP_LOG}"
    exit 1
fi

# Verify video was created successfully
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${VIDEO_FILE}" 2>/dev/null || echo "0")

if [ "$VIDEO_DURATION" = "0" ] || [ -z "$VIDEO_DURATION" ]; then
    echo "[ERROR] Video file is invalid" | tee -a "${TEMP_LOG}"
    exit 1
fi

echo "[$(date)] Test video created: ${VIDEO_FILE}" | tee -a "${TEMP_LOG}"
echo "[$(date)] Duration: ${VIDEO_DURATION}s" | tee -a "${TEMP_LOG}"

# Set proper permissions
chown -R ga:ga "${VIDEOS_DIR}"
chown -R ga:ga "${USER_HOME}/.config/vlc"
chown -R ga:ga "${USER_HOME}/.local/share/vlc"
chmod 755 "${PLAYLISTS_DIR}"
chmod 644 "${VIDEO_FILE}"

# Launch VLC without auto-playing so agent can configure
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_seamless_loop_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_seamless_loop_task.log
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

echo "[$(date)] Setup complete" | tee -a "${TEMP_LOG}"
echo "=== Configure Seamless Loop Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open the video: /home/ga/Videos/stream_background.mp4"
echo "  2. Create a playlist containing this video"
echo "  3. Save playlist as: /home/ga/Videos/playlists/stream_loop.m3u"
echo "     (Media → Save Playlist to File)"
echo "  4. Enable loop mode: Playback → Loop (or press 'L')"
echo "     OR enable repeat mode: Playback → Repeat (or press 'R')"
echo "  5. Configuration will be saved automatically"
echo ""
echo "Alternative workflow:"
echo "  1. Add video to playlist (Ctrl+L to open playlist, drag file)"
echo "  2. Enable loop/repeat from Playback menu"
echo "  3. Save playlist (Media → Save Playlist to File)"