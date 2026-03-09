#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stream to TV Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Kill any process using port 8080
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Port 8080 in use, killing process..."
    kill -9 $(lsof -t -i:8080) 2>/dev/null || true
    sleep 2
fi

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Check if nature_doc.mp4 exists, if not create it
VIDEO_FILE="/home/ga/Videos/nature_doc.mp4"
if [ ! -f "$VIDEO_FILE" ]; then
    echo "Creating sample video file nature_doc.mp4..."
    # Create a 42-second video (matching task description)
    # Using a simple test pattern with audio
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=42:size=1280x720:rate=30 \
               -f lavfi -i sine=frequency=440:duration=42 \
               -c:v libx264 -preset ultrafast -crf 28 \
               -c:a aac -b:a 128k \
               '$VIDEO_FILE' -y > /tmp/ffmpeg_create_video.log 2>&1"
    
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "ERROR: Failed to create video file"
        cat /tmp/ffmpeg_create_video.log
        exit 1
    fi
    
    chown ga:ga "$VIDEO_FILE"
    echo "✅ Video file created: $VIDEO_FILE"
else
    echo "✅ Video file exists: $VIDEO_FILE"
fi

# Verify video file
if [ ! -s "$VIDEO_FILE" ]; then
    echo "ERROR: Video file is empty"
    exit 1
fi

# Clean up any previous stream URL file
rm -f /home/ga/stream_url.txt

# Launch VLC GUI for agent to configure streaming
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_stream_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_stream_task.log
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

echo "=== Stream to TV Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Configure VLC to stream: /home/ga/Videos/nature_doc.mp4"
echo "  2. Use Media -> Stream (Ctrl+S)"
echo "  3. Add file: /home/ga/Videos/nature_doc.mp4"
echo "  4. Click Stream button (not Open!)"
echo "  5. Choose HTTP as destination, port 8080"
echo "  6. Get local IP (e.g., ip addr or hostname -I)"
echo "  7. Save stream URL to: /home/ga/stream_url.txt"
echo "  8. Format: http://<local_ip>:8080/"
echo ""
echo "Alternative CLI method:"
echo "  cvlc /home/ga/Videos/nature_doc.mp4 \\"
echo "    --sout '#standard{access=http,mux=ts,dst=:8080/}' \\"
echo "    --sout-keep --loop &"
echo "  echo \"http://\$(hostname -I | awk '{print \$1}'):8080/\" > /home/ga/stream_url.txt"