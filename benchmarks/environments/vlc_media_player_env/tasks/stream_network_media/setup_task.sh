#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stream Network Media Task ==="

kill_vlc ga
sleep 1

# Ensure Videos directory exists for playlist saving
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Stop any existing HTTP servers on port 8080
pkill -f "http.server 8080" || true
sleep 1

# Create test video if not exists (short video for streaming)
TEST_VIDEO="/home/ga/Videos/test_stream.mp4"
if [ ! -f "$TEST_VIDEO" ]; then
    echo "Creating test stream video..."
    # Create a 30-second test video with color bars and audio tone
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=30 \
           -f lavfi -i sine=frequency=1000:duration=30 \
           -pix_fmt yuv420p -c:v libx264 -c:a aac '$TEST_VIDEO' -y > /tmp/ffmpeg_stream.log 2>&1"
    
    if [ ! -f "$TEST_VIDEO" ]; then
        echo "ERROR: Failed to create test video"
        exit 1
    fi
    echo "✅ Test video created: $TEST_VIDEO"
fi

# Start simple HTTP server for streaming
echo "Starting HTTP server on port 8080..."
cd /home/ga/Videos
su - ga -c "cd /home/ga/Videos && python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &"
HTTP_PID=$!
echo $HTTP_PID > /tmp/http_server.pid

# Wait for server to start
sleep 2

# Verify server is running
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/test_stream.mp4 | grep -q "200"; then
    echo "WARNING: HTTP server may not be serving video correctly"
    cat /tmp/http_server.log || true
fi

# Create URL file on desktop
echo "Creating stream URL file on desktop..."
mkdir -p /home/ga/Desktop
echo "http://localhost:8080/test_stream.mp4" > /home/ga/Desktop/stream_url.txt
chown ga:ga /home/ga/Desktop/stream_url.txt

echo "Stream URL: $(cat /home/ga/Desktop/stream_url.txt)"

# Launch VLC with RC interface (no file, just VLC)
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 > /tmp/vlc_stream_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_stream_task.log || true
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

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Stream Network Media Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Network Stream dialog: Media → Open Network Stream (Ctrl+N)"
echo "  2. Copy URL from ~/Desktop/stream_url.txt:"
echo "     http://localhost:8080/test_stream.mp4"
echo "  3. Paste URL into network URL field and click Play"
echo "  4. Let stream play for at least 10 seconds"
echo "  5. Save stream to playlist:"
echo "     - Open playlist (Ctrl+L)"
echo "     - Media → Save Playlist to File"
echo "     - Save as: ~/Videos/company_streams.m3u"