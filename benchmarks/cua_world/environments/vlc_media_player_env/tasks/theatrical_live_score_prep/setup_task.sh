#!/bin/bash
echo "=== Setting up Theatrical Live-Score Sync Prep task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create project directories
SOURCE_DIR="/home/ga/Videos/live_score_project"
OUTPUT_DIR="/home/ga/Videos/live_score_deliverables"

mkdir -p "$SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"

# 1. Generate 24fps master file (60 seconds exactly = 1440 frames)
echo "Generating 24fps source video..."
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=60" \
  -vf "drawtext=text='1920s SILENT FILM MASTER':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.5, drawtext=text='24 FPS TRANSFER':x=(w-text_w)/2:y=(h-text_h)/2+80:fontsize=48:fontcolor=yellow" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p -an \
  "$SOURCE_DIR/metropolis_master_24fps.mp4" 2>/dev/null

# 2. Generate conductor clicks (80 seconds audio track)
echo "Generating conductor audio track..."
ffmpeg -y -f lavfi -i "sine=frequency=880:sample_rate=44100:duration=80" \
  -af "volume=0.5" -c:a aac -b:a 128k -ac 2 \
  "$SOURCE_DIR/conductor_clicks.wav" 2>/dev/null

# 3. Create specifications document
cat > "$SOURCE_DIR/specifications.txt" << 'EOF'
THEATRICAL LIVE-SCORE DELIVERY SPECS

Original Source: metropolis_master_24fps.mp4 (60 seconds, 24fps)
Target Playback: 18 fps (Requires 80 second duration to preserve all frames)
Click Track: conductor_clicks.wav (80 seconds, strictly timed)

DELIVERABLE 1: projection_master.mp4
- Video: H.264, 18 fps
- Duration: 80.0 seconds
- Audio: None (Silent)

DELIVERABLE 2: conductor_reference.mp4
- Video: H.264, 18 fps
- Duration: 80.0 seconds
- Audio: Stereo (multiplexed with conductor_clicks.wav)
- Overlay: Visual timecode in the top-right corner of the video.

DELIVERABLE 3: delivery_manifest.json
- Valid JSON file listing both outputs with duration, framerate, and has_audio boolean.

Output Folder: /home/ga/Videos/live_score_deliverables/
EOF

# Fix permissions
chown -R ga:ga /home/ga/Videos

# Ensure VLC is running (maximized and focused)
if ! pgrep -f "vlc" > /dev/null; then
    echo "Starting VLC..."
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &"
    sleep 3
fi

DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="