#!/bin/bash
# Setup script for stopmotion_assembly_pipeline task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up stopmotion_assembly_pipeline task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

kill_vlc || true

# Create required directories
mkdir -p /home/ga/Videos/stopmotion_frames
mkdir -p /home/ga/Videos/stopmotion_output
mkdir -p /home/ga/Music
mkdir -p /home/ga/Documents

echo "Downloading real video source..."
# Try to get a real public domain video (Big Buck Bunny sample)
if ! curl -sL "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4" -o /tmp/source.mp4; then
    echo "Fallback: generating complex synthetic source due to network issue..."
    # Generate a visually complex fractal zoom if network download fails
    ffmpeg -y -f lavfi -i "mandelbrot=size=1280x720:rate=24:duration=10" -c:v libx264 -preset ultrafast /tmp/source.mp4 2>/dev/null
fi

echo "Extracting 120 frames..."
# Extract exactly 120 frames into the stopmotion_frames directory
ffmpeg -y -i /tmp/source.mp4 -vf "fps=12,scale=1280:720" -vframes 120 /home/ga/Videos/stopmotion_frames/frame_%03d.png 2>/dev/null

echo "Downloading real audio source..."
# Try to get a real audio sample
if ! curl -sL "https://actions.google.com/sounds/v1/water/small_stream_flowing.ogg" -o /tmp/audio.ogg; then
    echo "Fallback: generating synthetic audio..."
    ffmpeg -y -f lavfi -i "anoisesrc=c=pink:r=44100:a=0.5,aecho=0.8:0.9:1000:0.3" -t 10 /tmp/audio.ogg 2>/dev/null
fi

echo "Creating commercial soundtrack..."
# Ensure it is exactly 10 seconds, 44.1kHz stereo WAV
ffmpeg -y -i /tmp/audio.ogg -t 10 -c:a pcm_s16le -ar 44100 -ac 2 /home/ga/Music/commercial_soundtrack.wav 2>/dev/null

echo "Writing production brief..."
cat > /home/ga/Documents/production_brief.txt << 'BRIEFEOF'
=== STOP-MOTION COMMERCIAL PRODUCTION BRIEF ===
Project: Q3 Stop-Motion Promo
Source Material: 120 PNG frames (frame_001.png to frame_120.png)
Source Audio: commercial_soundtrack.wav (10s)

REQUIRED DELIVERABLES (Save to /home/ga/Videos/stopmotion_output/):

1. commercial_master.mp4
   - Framerate: 12 fps
   - Resolution: 1280x720
   - Audio: Include soundtrack (muxed)
   - Duration: ~10 seconds

2. commercial_cinematic.mp4
   - Framerate: 24 fps (fast motion, double speed)
   - Resolution: 1280x720
   - Audio: NONE (silent)
   - Duration: ~5 seconds

3. commercial_web.mp4
   - Framerate: 12 fps
   - Resolution: 640x360 (downscaled)
   - Audio: Include soundtrack (muxed)
   - Duration: ~10 seconds
   - Note: File size must be smaller than master

4. commercial_preview.mp4
   - Source: Only every 10th frame (frame_001, frame_011, frame_021, etc.) = 12 frames total
   - Framerate: 2 fps (each frame held 0.5s)
   - Resolution: 640x360
   - Audio: NONE (silent)
   - Duration: ~6 seconds

5. proof_sheet.png
   - A single image containing a grid of 12 key frames
   - Minimum dimensions: 1200x800 pixels

6. assembly_manifest.json
   - A JSON file documenting the project
   - Must contain:
     - "project_name": "StopMotion Commercial"
     - "total_frames": 120
     - "source_resolution": "1280x720"
     - "deliverables": [array of objects with "filename", "duration_seconds", "resolution", "has_audio" (boolean)]

Deadline is immediately. Follow specifications exactly.
BRIEFEOF

# Fix permissions
chown -R ga:ga /home/ga/Videos /home/ga/Music /home/ga/Documents

# Launch a terminal and file manager to help the agent get started
su - ga -c "DISPLAY=:1 nautilus /home/ga/Videos/stopmotion_frames &" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Videos/stopmotion_output &" 2>/dev/null || true
sleep 2

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="