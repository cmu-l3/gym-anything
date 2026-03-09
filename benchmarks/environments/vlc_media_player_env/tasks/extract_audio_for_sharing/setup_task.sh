#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Audio for Sharing Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Music
chown ga:ga /home/ga/Music

# Create source video file (simulating lecture recording)
# Using ffmpeg to generate a ~90-second video with audio
VIDEO_FILE="/home/ga/Videos/lecture_recording.mp4"

echo "Creating source lecture video..."
ffmpeg -f lavfi -i testsrc=duration=90:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=440:duration=90 \
       -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k \
       "$VIDEO_FILE" \
       -y 2>/tmp/task_setup.log

chown ga:ga "$VIDEO_FILE"

# Verify source file was created
if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to create source video"
    cat /tmp/task_setup.log
    exit 1
fi

echo "✅ Source video created: $(ls -lh $VIDEO_FILE)"

# Clean any previous output
rm -f /home/ga/Music/lecture_audio.mp3

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_extract_audio_task.log 2>&1 &"

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

echo "=== Extract Audio for Sharing Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Convert /home/ga/Videos/lecture_recording.mp4 to audio-only MP3"
echo "  2. Use Media -> Convert/Save (Ctrl+R)"
echo "  3. Add source file: /home/ga/Videos/lecture_recording.mp4"
echo "  4. Click Convert/Save button"
echo "  5. Choose audio profile (e.g., Audio - MP3)"
echo "  6. Set destination: /home/ga/Music/lecture_audio.mp3"
echo "  7. Start conversion"
echo ""
echo "Expected output: /home/ga/Music/lecture_audio.mp3"