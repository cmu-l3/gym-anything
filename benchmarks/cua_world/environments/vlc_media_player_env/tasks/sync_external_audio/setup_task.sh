#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sync External Audio Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos/audio_sync_test
mkdir -p /home/ga/Music/external_audio
chown -R ga:ga /home/ga/Videos/audio_sync_test
chown -R ga:ga /home/ga/Music/external_audio

# Generate test video with very quiet/poor audio (simulating bad recording)
echo "Generating test video with poor audio..."
VIDEO_FILE="/home/ga/Videos/audio_sync_test/video_poor_audio.mp4"

# Create 30-second video with color test pattern and very quiet sine wave
ffmpeg -y -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=440:duration=30 \
       -filter_complex "[1:a]volume=0.05[aquiet]" \
       -map 0:v -map "[aquiet]" \
       -c:v libx264 -preset ultrafast -c:a aac -b:a 32k \
       "$VIDEO_FILE" > /tmp/ffmpeg_video_gen.log 2>&1

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to generate test video"
    cat /tmp/ffmpeg_video_gen.log
    exit 1
fi

echo "✅ Test video created: $VIDEO_FILE"

# Generate high-quality external audio file (same duration, louder)
echo "Generating external audio file..."
AUDIO_FILE="/home/ga/Music/external_audio/replacement_audio.mp3"

# Create 30-second audio with clear, loud sine wave at different frequency
ffmpeg -y -f lavfi -i sine=frequency=880:duration=30 \
       -af "volume=0.7" \
       -c:a libmp3lame -b:a 192k \
       "$AUDIO_FILE" > /tmp/ffmpeg_audio_gen.log 2>&1

if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR: Failed to generate external audio"
    cat /tmp/ffmpeg_audio_gen.log
    exit 1
fi

echo "✅ External audio created: $AUDIO_FILE"

# Set proper ownership
chown ga:ga "$VIDEO_FILE"
chown ga:ga "$AUDIO_FILE"

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$VIDEO_FILE' > /tmp/vlc_audio_sync_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_sync_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Record initial audio track state
echo "Recording initial audio track state..."
INITIAL_ATRACK=$(echo "atrack" | nc -w 2 localhost 9999 2>/dev/null | grep -oP '(?:>|track:)\s*\K\d+' | head -1 || echo "1")
echo "$INITIAL_ATRACK" > /tmp/vlc_initial_atrack.txt

echo "=== Sync External Audio Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing video with poor/quiet audio"
echo "  2. Load external audio file:"
echo "     - Navigate to: Audio → Audio Track → Load File..."
echo "     - Browse to: /home/ga/Music/external_audio/"
echo "     - Select: replacement_audio.mp3"
echo "  3. Switch to external audio track:"
echo "     - Navigate to: Audio → Audio Track"
echo "     - Select the newly loaded track (Track 2 or similar)"
echo "  4. Verify louder, clearer audio is now playing"
echo ""
echo "📁 Files:"
echo "  Video: $VIDEO_FILE"
echo "  External Audio: $AUDIO_FILE"