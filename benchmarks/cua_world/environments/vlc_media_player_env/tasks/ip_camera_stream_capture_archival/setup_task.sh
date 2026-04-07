#!/bin/bash
echo "=== Setting up IP Camera Stream Capture Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create required directories for the agent
su - ga -c "mkdir -p /home/ga/Videos/camera_archive"
su - ga -c "mkdir -p /home/ga/Pictures/vlc"
su - ga -c "mkdir -p /home/ga/Documents"

# Ensure clean state
killall vlc 2>/dev/null || true
killall cvlc 2>/dev/null || true
rm -f /home/ga/Videos/camera_archive/cam01_capture.mp4
rm -f /home/ga/Pictures/vlc/*.png
rm -f /home/ga/Documents/stream_report.json

# 1. Generate a source video with legacy codecs to act as the camera feed
echo "Generating source video stream..."
ffmpeg -y -f lavfi -i "testsrc2=size=640x480:rate=25:duration=120" \
    -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=120" \
    -drawtext "text='CAM01 LIVE %{localtime}':x=20:y=20:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5" \
    -c:v mpeg2video -b:v 1500k \
    -c:a mp2 -b:a 128k \
    /tmp/source_camera.ts > /tmp/ffmpeg_gen.log 2>&1

# 2. Serve the video as a continuous HTTP live stream using headless VLC (cvlc)
echo "Starting IP camera stream server on http://127.0.0.1:8080/cam01..."
su - ga -c "cvlc -q /tmp/source_camera.ts --sout '#standard{access=http,mux=ts,dst=:8080/cam01}' --loop --sout-keep > /dev/null 2>&1 &"

# Wait for the stream to become available
for i in {1..15}; do
    if curl --max-time 2 -s http://127.0.0.1:8080/cam01 | head -c 10 > /dev/null; then
        echo "Stream is LIVE!"
        break
    fi
    sleep 1
done

# Launch VLC UI for the agent
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show > /dev/null 2>&1 &"

# Wait for VLC window to appear and maximize it
sleep 3
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="