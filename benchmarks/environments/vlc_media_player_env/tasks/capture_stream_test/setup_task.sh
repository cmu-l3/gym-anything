#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Capture Stream Test Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Videos

# Stop any existing HTTP servers on port 8080
if [ -f /tmp/http_stream_server.pid ]; then
    OLD_PID=$(cat /tmp/http_stream_server.pid)
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Stopping old HTTP server (PID: $OLD_PID)..."
        kill "$OLD_PID" || true
        sleep 1
    fi
    rm -f /tmp/http_stream_server.pid
fi

# Also check for any python http.server on port 8080
pkill -f "python.*http.server.*8080" || true
sleep 1

# Start HTTP server to serve test stream
echo "Starting HTTP stream server..."
cd /home/ga/Videos

# Start server as ga user
su - ga -c "cd /home/ga/Videos && python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &"
sleep 2

# Get the server PID
HTTP_PID=$(pgrep -f "python.*http.server.*8080" | head -1)
if [ -n "$HTTP_PID" ]; then
    echo "$HTTP_PID" > /tmp/http_stream_server.pid
    echo "✅ HTTP server started (PID: $HTTP_PID)"
else
    echo "ERROR: Failed to start HTTP server"
    exit 1
fi

# Write stream URL to file
STREAM_URL="http://localhost:8080/sample_video.mp4"
echo "$STREAM_URL" > /home/ga/stream_url.txt
chown ga:ga /home/ga/stream_url.txt
echo "Stream URL: $STREAM_URL"

# Verify stream is accessible
echo "Verifying stream is accessible..."
for i in {1..5}; do
    if curl -s --head "$STREAM_URL" | grep "200 OK" > /dev/null; then
        echo "✅ Stream is accessible"
        break
    fi
    echo "Waiting for stream to be ready..."
    sleep 1
done

# Remove any existing test recording
rm -f /home/ga/Videos/stream_test_capture.mp4

# Configure VLC to save recordings to Videos directory
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Set recording directory
    if grep -q "^input-record-path=" "$VLC_RC"; then
        sed -i "s|^input-record-path=.*|input-record-path=/home/ga/Videos|" "$VLC_RC"
    else
        echo "input-record-path=/home/ga/Videos" >> "$VLC_RC"
    fi
fi

# Launch VLC (empty, agent will open stream)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 > /tmp/vlc_stream_test_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

echo "=== Capture Stream Test Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Stream URL is in: /home/ga/stream_url.txt"
echo "  2. Open Media → Open Network Stream (Ctrl+N)"
echo "  3. Paste the stream URL and click Play"
echo "  4. Enable View → Advanced Controls to show record button"
echo "  5. Click the Record button (red circle) to start recording"
echo "  6. Wait approximately 20 seconds"
echo "  7. Click Record button again to stop"
echo "  8. Output should be saved to: /home/ga/Videos/stream_test_capture.mp4"