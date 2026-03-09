#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stress Test Playback Stability Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create test video if it doesn't exist
TEST_VIDEO="/home/ga/Videos/test_lecture.mp4"
if [ ! -f "$TEST_VIDEO" ]; then
    echo "Creating test video for stress testing..."
    
    # Generate a 2-minute test video with color patterns and audio tone
    # This creates a valid video file that exercises VLC's playback
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=120:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=440:duration=120 \
        -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k \
        '$TEST_VIDEO' -y > /tmp/ffmpeg_generate.log 2>&1"
    
    if [ ! -f "$TEST_VIDEO" ]; then
        echo "ERROR: Failed to create test video"
        cat /tmp/ffmpeg_generate.log
        exit 1
    fi
    
    chown ga:ga "$TEST_VIDEO"
    echo "✅ Test video created: $TEST_VIDEO (2 minutes)"
else
    echo "Test video already exists: $TEST_VIDEO"
fi

# Ensure result output directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Launch VLC with test video and verbose logging
echo "Launching VLC with verbose logging..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc \
    --avcodec-hw=none \
    --no-video-title-show \
    --verbose=2 \
    '$TEST_VIDEO' \
    > /tmp/vlc_stability_test.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_stability_test.log || true
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

# Wait for video to start playing
sleep 2

# Verify video is playing
echo "Verifying video playback started..."
if ! is_vlc_running; then
    echo "ERROR: VLC is not running"
    exit 1
fi

echo "=== Stress Test Playback Stability Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing test_lecture.mp4 (2 minutes) at normal speed"
echo "  2. Increase playback speed to 4x:"
echo "     - Press ']' (right bracket) 3 times"
echo "     - Or use Playback → Speed → Faster"
echo "  3. Wait for at least 80% of playback to complete (~25 seconds)"
echo "  4. Verify VLC remains stable (doesn't crash or freeze)"
echo "  5. Document results in /home/ga/Videos/stress_test_result.txt"
echo ""
echo "At 4x speed: 120 seconds of video = 30 seconds real time"
echo "Target: Wait at least 24 seconds (80% of 30s)"