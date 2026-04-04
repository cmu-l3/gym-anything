#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Capture Stream Recording Task ==="

kill_vlc ga
sleep 1

# Create output directory
mkdir -p /home/ga/Videos/captures
chown ga:ga /home/ga/Videos/captures

# Clean any previous recordings
rm -f /home/ga/Videos/captures/recorded_stream.mp4

# Set up HTTP server with sample video (simulates live stream)
echo "Setting up stream source..."
mkdir -p /tmp/stream_source

# Use existing sample video
if [ -f /home/ga/Videos/sample_video.mp4 ]; then
    cp /home/ga/Videos/sample_video.mp4 /tmp/stream_source/live_stream.mp4
    echo "✅ Using sample_video.mp4 as stream source"
elif [ -f /home/ga/Videos/color_test.mp4 ]; then
    cp /home/ga/Videos/color_test.mp4 /tmp/stream_source/live_stream.mp4
    echo "✅ Using color_test.mp4 as stream source"
else
    echo "ERROR: No sample video found"
    exit 1
fi

# Start simple HTTP server on port 8080 in background
echo "Starting HTTP server on port 8080..."
cd /tmp/stream_source
nohup python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &
HTTP_SERVER_PID=$!
echo $HTTP_SERVER_PID > /tmp/stream_server.pid

# Wait for server to be ready
sleep 3

# Verify server is responding
if command -v curl &> /dev/null; then
    for i in {1..5}; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/live_stream.mp4 | grep -q "200"; then
            echo "✅ HTTP server responding correctly"
            break
        fi
        echo "Waiting for HTTP server... attempt $i"
        sleep 1
    done
else
    # Fallback: just check if process is running
    if ps -p $HTTP_SERVER_PID > /dev/null; then
        echo "✅ HTTP server process running (PID: $HTTP_SERVER_PID)"
    fi
fi

# Save stream URL to file for reference
echo "http://localhost:8080/live_stream.mp4" > /tmp/stream_url.txt
chown ga:ga /tmp/stream_url.txt

# Launch VLC without auto-playing stream
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_stream_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    # Clean up HTTP server
    if [ -f /tmp/stream_server.pid ]; then
        kill $(cat /tmp/stream_server.pid) 2>/dev/null || true
    fi
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    # Clean up HTTP server
    if [ -f /tmp/stream_server.pid ]; then
        kill $(cat /tmp/stream_server.pid) 2>/dev/null || true
    fi
    exit 1
fi

# Click on center of screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 1

echo "=== Capture Stream Recording Task Setup Complete ==="
echo ""
echo "📺 Stream Server Ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Task Instructions:"
echo ""
echo "You need to record a network video stream for later viewing."
echo ""
echo "Stream URL: http://localhost:8080/live_stream.mp4"
echo ""
echo "Steps to complete the task:"
echo ""
echo "1. Open network stream recording dialog:"
echo "   Option A: Media → Convert/Save (Ctrl+R)"
echo "            Then click 'Network' tab"
echo "            Enter the URL"
echo "   "
echo "   Option B: Media → Open Network Stream (Ctrl+N)"
echo "            Enter the URL"
echo "            Click 'Convert/Save' button (in dropdown next to Play)"
echo ""
echo "2. In the Convert dialog:"
echo "   - Select a conversion profile (e.g., 'Video - H.264 + MP3 (MP4)')"
echo "   - Set destination file: /home/ga/Videos/captures/recorded_stream.mp4"
echo ""
echo "3. Click 'Start' to begin recording"
echo ""
echo "4. Let the recording run for at least 30 seconds"
echo ""
echo "5. Stop the recording:"
echo "   - Close VLC (Ctrl+Q) or"
echo "   - Use Media → Stop Recording/Streaming"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  Important: Use 'Convert/Save' NOT just 'Play'"
echo "    Playing the stream won't save it to a file!"
echo ""