#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Extract Audio Podcast Task ==="

kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos/conferences
mkdir -p /home/ga/Music/podcasts
mkdir -p /home/ga/Documents/task_info

# Clear any existing output files
rm -f /home/ga/Music/podcasts/*.mp3

# Generate a conference video with clear audio track
log_info "Generating conference video with audio track..."

# Create a 2-minute (120 second) video with test pattern and audio
# Using testsrc for video and sine wave for audio to simulate speech
ffmpeg -y -f lavfi \
    -i "testsrc=duration=120:size=1280x720:rate=30" \
    -f lavfi \
    -i "sine=frequency=440:duration=120" \
    -c:v libx264 -preset ultrafast -crf 23 \
    -c:a aac -b:a 192k -ac 2 -ar 44100 \
    /home/ga/Videos/conferences/Tech_Conference_2024.mp4 \
    > /tmp/ffmpeg_generate.log 2>&1

# Verify source video was created
if [ ! -f /home/ga/Videos/conferences/Tech_Conference_2024.mp4 ]; then
    log_error "Failed to create source video"
    cat /tmp/ffmpeg_generate.log
    exit 1
fi

SOURCE_SIZE=$(stat -c%s /home/ga/Videos/conferences/Tech_Conference_2024.mp4)
log_info "Source video created: $((SOURCE_SIZE / 1024 / 1024))MB"

# Verify video properties using ffprobe
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 \
    /home/ga/Videos/conferences/Tech_Conference_2024.mp4 > /tmp/source_duration.txt 2>&1 || true

# Store task information
cat > /home/ga/Documents/task_info/audio_extraction_task.txt << EOF
Conference Audio Extraction Task
=================================

Source Video: /home/ga/Videos/conferences/Tech_Conference_2024.mp4
Target Output: /home/ga/Music/podcasts/Tech_Conference_2024.mp3

Instructions:
1. Open VLC (should launch automatically)
2. Use Media -> Convert/Save (Ctrl+R)
3. Add source file: /home/ga/Videos/conferences/Tech_Conference_2024.mp4
4. Click "Convert/Save" button
5. Choose profile: "Audio - MP3" (128-192 kbps recommended)
6. Set destination: /home/ga/Music/podcasts/Tech_Conference_2024.mp3
7. Click "Start" to begin conversion
8. Wait for conversion to complete

The extracted audio should be significantly smaller than the original video
while maintaining good quality for speech/podcast listening.
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos/conferences
chown -R ga:ga /home/ga/Music/podcasts
chown -R ga:ga /home/ga/Documents/task_info

# Launch VLC without opening any file (agent needs to use Convert/Save dialog)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_extract_audio_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    log_error "VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    log_error "VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

log_info "Task setup complete"
log_info "Source: /home/ga/Videos/conferences/Tech_Conference_2024.mp4"
log_info "Expected output: /home/ga/Music/podcasts/Tech_Conference_2024.mp3"

echo "=== Extract Audio Podcast Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Media -> Convert/Save (Ctrl+R)"
echo "  2. Add source: /home/ga/Videos/conferences/Tech_Conference_2024.mp4"
echo "  3. Click 'Convert/Save' button"
echo "  4. Profile: Select 'Audio - MP3'"
echo "  5. Destination: /home/ga/Music/podcasts/Tech_Conference_2024.mp3"
echo "  6. Start conversion and wait for completion"