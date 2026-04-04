#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Karaoke Track Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure Music directory exists
mkdir -p /home/ga/Music
chown ga:ga /home/ga/Music

# Generate a stereo test audio file with prominent center content (simulated vocals)
# This creates a 30-second test track with:
# - Background music in stereo (L+R different phases)
# - "Vocals" (specific frequency) in center (L+R identical)
echo "[SETUP] Generating practice song with center-channel vocals..."

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found, cannot generate test audio"
    exit 1
fi

# Create a 30-second audio with center vocals and stereo backing
# The center channel (vocals) is a 440Hz sine wave
# The stereo content is pink noise with different phase in L/R
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=30" \
       -f lavfi -i "sine=frequency=220:duration=30" \
       -f lavfi -i "sine=frequency=330:duration=30" \
       -filter_complex "\
         [0:a]volume=0.6[vocals];\
         [1:a]volume=0.4,aphaser[left_bg];\
         [2:a]volume=0.4,aphaser=delay=5[right_bg];\
         [vocals][vocals]amerge=inputs=2[vocal_stereo];\
         [left_bg][right_bg]amerge=inputs=2[bg_stereo];\
         [vocal_stereo][bg_stereo]amix=inputs=2:duration=shortest:weights=1 1" \
       -codec:a libmp3lame -b:a 192k -ar 44100 -ac 2 \
       /home/ga/Music/practice_song.mp3 \
       > /tmp/ffmpeg_karaoke_setup.log 2>&1

# Verify the file was created
if [ ! -f /home/ga/Music/practice_song.mp3 ]; then
    echo "ERROR: Failed to generate practice song"
    cat /tmp/ffmpeg_karaoke_setup.log
    exit 1
fi

# Get file info
FILE_SIZE=$(stat -c%s /home/ga/Music/practice_song.mp3 2>/dev/null || stat -f%z /home/ga/Music/practice_song.mp3 2>/dev/null)
echo "[SETUP] Created practice_song.mp3 (${FILE_SIZE} bytes)"

# Verify with ffprobe
if command -v ffprobe &> /dev/null; then
    echo "[SETUP] Verifying audio properties..."
    ffprobe -v error -show_entries stream=codec_name,channels,sample_rate,duration \
            -of default=noprint_wrappers=1 \
            /home/ga/Music/practice_song.mp3 || true
fi

# Set ownership
chown -R ga:ga /home/ga/Music/

# Remove any existing karaoke output from previous runs
rm -f /home/ga/Music/karaoke_version.mp3

# Launch VLC (without opening any file initially, agent will open it)
echo "[SETUP] Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_karaoke_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_karaoke_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "[SETUP] Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Create Karaoke Track Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open the practice song: /home/ga/Music/practice_song.mp3"
echo "  2. Apply audio filters to reduce center-channel vocals:"
echo "     Method A: Use Tools → Effects and Filters (Ctrl+E)"
echo "               → Audio Effects → Configure spatializer/channel mixer"
echo "               Then use Media → Convert/Save"
echo "     Method B: Use Media → Convert/Save directly with filter options"
echo "  3. Save the filtered audio to: /home/ga/Music/karaoke_version.mp3"
echo "  4. Ensure output is MP3 format, stereo, similar duration"
echo ""
echo "Input file: /home/ga/Music/practice_song.mp3 (~30 seconds)"
echo "Output file: /home/ga/Music/karaoke_version.mp3"