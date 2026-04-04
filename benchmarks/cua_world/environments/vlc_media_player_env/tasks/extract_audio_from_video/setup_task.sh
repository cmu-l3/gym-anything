#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Audio from Video Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Music/extracted
chown -R ga:ga /home/ga/Music/extracted

# Remove any existing output file
rm -f /home/ga/Music/extracted/practice_audio.mp3

# Generate source video with audio (simulating band practice recording)
echo "Generating source video with audio track..."
SOURCE_VIDEO="/home/ga/Videos/band_practice.mp4"

# Create a ~45 second video with stereo audio (simulating phone recording)
# Using sine waves at different frequencies to simulate instruments
ffmpeg -f lavfi -i testsrc=duration=45:size=640x480:rate=30 \
       -f lavfi -i "sine=frequency=220:duration=45" \
       -f lavfi -i "sine=frequency=330:duration=45" \
       -filter_complex "[1:a][2:a]amerge=inputs=2[aout]" \
       -map 0:v -map "[aout]" \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k -ac 2 -ar 44100 \
       "$SOURCE_VIDEO" -y 2>&1 | tail -5

if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: Failed to create source video"
    exit 1
fi

# Verify source video has audio
AUDIO_CHECK=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_type -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null || echo "")
if [ "$AUDIO_CHECK" != "audio" ]; then
    echo "ERROR: Source video has no audio stream"
    exit 1
fi

chown ga:ga "$SOURCE_VIDEO"
echo "✅ Source video created: $SOURCE_VIDEO"

# Get source video duration for reference
SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null || echo "0")
echo "Source video duration: ${SOURCE_DURATION}s"

# Launch VLC without auto-playing any file
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_extract_audio_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_extract_audio_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Extract Audio from Video Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open Media → Convert/Save (or press Ctrl+R)"
echo "  2. Click 'Add...' button"
echo "  3. Navigate to /home/ga/Videos/ and select band_practice.mp4"
echo "  4. Click 'Convert/Save' dropdown and select 'Convert'"
echo "  5. Click 'Browse' for destination"
echo "  6. Navigate to /home/ga/Music/extracted/"
echo "  7. Enter filename: practice_audio.mp3"
echo "  8. From 'Profile' dropdown, select 'Audio - MP3'"
echo "  9. (Optional) Click wrench icon to customize: bitrate=192kb/s, channels=2"
echo " 10. Click 'Start' to begin extraction"
echo ""
echo "📂 Source: /home/ga/Videos/band_practice.mp4"
echo "📂 Target: /home/ga/Music/extracted/practice_audio.mp3"
echo "🎵 Required: MP3 format, 192 kbps, stereo"