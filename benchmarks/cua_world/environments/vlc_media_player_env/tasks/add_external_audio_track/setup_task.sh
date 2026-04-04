#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Add External Audio Track Task ==="

kill_vlc ga
sleep 1

# Ensure output directories exist
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Check if ffmpeg is available, install if not
if ! command -v ffmpeg &> /dev/null; then
    echo "Installing ffmpeg..."
    apt-get update -qq
    apt-get install -y -qq ffmpeg
fi

# Create test video with 440 Hz audio tone (60 seconds)
echo "Creating test video with 440 Hz audio..."
ffmpeg -f lavfi -i testsrc=duration=60:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=440:duration=60 \
       -pix_fmt yuv420p -y /home/ga/Videos/sample_movie.mp4 \
       > /tmp/ffmpeg_video.log 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create video file"
    cat /tmp/ffmpeg_video.log
    exit 1
fi

# Create commentary audio with 880 Hz tone (60 seconds)
# This audio is meant to be played with +3 second delay
echo "Creating commentary audio with 880 Hz tone..."
ffmpeg -f lavfi -i sine=frequency=880:duration=60 \
       -y /home/ga/Videos/commentary.mp3 \
       > /tmp/ffmpeg_audio.log 2>&1

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create audio file"
    cat /tmp/ffmpeg_audio.log
    exit 1
fi

# Set ownership
chown ga:ga /home/ga/Videos/sample_movie.mp4 2>/dev/null || true
chown ga:ga /home/ga/Videos/commentary.mp3 2>/dev/null || true

# Verify files were created
if [ ! -f /home/ga/Videos/sample_movie.mp4 ]; then
    echo "ERROR: Video file not created"
    exit 1
fi

if [ ! -f /home/ga/Videos/commentary.mp3 ]; then
    echo "ERROR: Commentary audio not created"
    exit 1
fi

echo "✅ Media files created:"
ls -lh /home/ga/Videos/sample_movie.mp4
ls -lh /home/ga/Videos/commentary.mp3

# Create info file explaining the task
cat > /home/ga/Videos/TASK_INFO.txt << 'EOF'
TASK: Add External Audio Track and Synchronize

Files:
  - sample_movie.mp4 (440 Hz tone)
  - commentary.mp3 (880 Hz tone)

Goal:
  Load commentary.mp3 as an external audio track and set +3000ms delay
  so both audio tracks play in sync.

Steps:
  1. Audio → Audio Track → Load File
  2. Select /home/ga/Videos/commentary.mp3
  3. Tools → Track Synchronization
  4. Set "Audio track synchronization" to +3.000 s (or 3000 ms)
  5. Close dialog to apply

When synced correctly:
  Both 440 Hz and 880 Hz tones should play simultaneously.
EOF

chown ga:ga /home/ga/Videos/TASK_INFO.txt 2>/dev/null || true

# Reset VLC audio delay to default (0)
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname "$VLC_RC")"
if [ -f "$VLC_RC" ]; then
    # Remove any existing audio delay settings
    sed -i '/^audio-desync=/d' "$VLC_RC"
    sed -i '/^audio-time-stretch/d' "$VLC_RC"
    sed -i '/^sub-file=/d' "$VLC_RC"
    echo "Audio delay settings reset"
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Videos/sample_movie.mp4 > /tmp/vlc_audio_track_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_track_task.log
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
    echo "RC interface not ready, waiting..."
    sleep 1
done

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Trigger window rendering
echo "Triggering window rendering..."
su - ga -c "DISPLAY=:1 xdotool mousemove 400 300 click 1" || true
sleep 1

echo "=== Add External Audio Track Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing sample_movie.mp4 (440 Hz audio)"
echo "  2. Load external audio track:"
echo "     - Audio → Audio Track → Load File"
echo "     - Select: /home/ga/Videos/commentary.mp3"
echo "  3. Synchronize audio tracks:"
echo "     - Tools → Track Synchronization"
echo "     - Set 'Audio track synchronization' to +3.000 s (3000 ms)"
echo "  4. Close dialog to apply"
echo ""
echo "Expected result: Both audio tones (440 Hz + 880 Hz) play together"