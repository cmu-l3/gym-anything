#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Record Network Stream Task ==="

kill_vlc ga
sleep 1

# Create recordings output directory
RECORDINGS_DIR="/home/ga/Videos/recordings"
mkdir -p "$RECORDINGS_DIR"
chown -R ga:ga "$RECORDINGS_DIR"

# Clear any previous recordings
rm -f "$RECORDINGS_DIR"/captured_webinar.mp4
rm -f "$RECORDINGS_DIR"/*.mp4

# Create or verify test stream source exists
TEST_STREAM="/home/ga/Videos/test_stream.mp4"

if [ ! -f "$TEST_STREAM" ]; then
    echo "Creating test stream video (simulating live stream)..."
    
    # Generate a 30-second test video with color bars and audio tone
    # This simulates a webinar/conference stream
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=25 \
        -f lavfi -i sine=frequency=440:duration=30 \
        -pix_fmt yuv420p -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
        '$TEST_STREAM' -y > /tmp/stream_gen.log 2>&1" || {
        echo "ERROR: Failed to generate test stream"
        cat /tmp/stream_gen.log
        exit 1
    }
    
    echo "✅ Test stream created: $TEST_STREAM"
else
    echo "✅ Test stream already exists: $TEST_STREAM"
fi

# Verify test stream is valid
if [ ! -s "$TEST_STREAM" ]; then
    echo "ERROR: Test stream file is empty"
    exit 1
fi

TEST_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TEST_STREAM" 2>/dev/null || echo "0")
if (( $(echo "$TEST_DURATION < 20" | bc -l) )); then
    echo "ERROR: Test stream is too short: ${TEST_DURATION}s"
    exit 1
fi

echo "Test stream duration: ${TEST_DURATION}s"

# Launch VLC (without opening any file initially)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_record_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_record_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_record_task.log
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 1
fi

# Log setup information
cat > /tmp/vlc_record_setup.log <<EOF
=== VLC Network Stream Recording Setup ===
Timestamp: $(date)
Test stream: $TEST_STREAM
Test stream duration: ${TEST_DURATION}s
Output directory: $RECORDINGS_DIR
Expected output: $RECORDINGS_DIR/captured_webinar.mp4
Stream URL to use: file://$TEST_STREAM
EOF

echo "=== Record Network Stream Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open Media → Convert/Save (Ctrl+R)"
echo "  2. Click on the 'Network' tab"
echo "  3. Enter stream URL: file://$TEST_STREAM"
echo "  4. Click 'Convert/Save' button (NOT 'Play'!)"
echo "  5. In the Convert dialog:"
echo "     - Profile: Select 'Video - H.264 + MP3 (MP4)' or similar"
echo "     - Destination: Click Browse, navigate to $RECORDINGS_DIR"
echo "     - Filename: captured_webinar.mp4"
echo "  6. Click 'Start' to begin recording"
echo "  7. Let recording run for at least 10-15 seconds"
echo "  8. VLC will stop automatically when stream ends"
echo ""
echo "💡 Tip: The Convert/Save dialog has multiple tabs - make sure you're on 'Network'"