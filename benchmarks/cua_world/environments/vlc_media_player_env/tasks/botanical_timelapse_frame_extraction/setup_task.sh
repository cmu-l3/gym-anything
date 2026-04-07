#!/bin/bash
echo "=== Setting up Botanical Timelapse Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Videos/bloom_clips
mkdir -p /home/ga/Pictures/bloom_frames
mkdir -p /home/ga/Documents

# Generate the raw source video
# We use a moving test pattern with a hue shift and audio to simulate varied frames
echo "Generating source video..."
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=60" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=60" \
  -vf "hue=H=t*PI/15,drawtext=text='Queen of the Night Bloom - %{pts\:hms}':x=50:y=50:fontsize=64:fontcolor=white:box=1:boxcolor=black@0.6" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k \
  /home/ga/Videos/flower_bloom_raw.mp4 2>/dev/null

# Set ownership
chown -R ga:ga /home/ga/Videos /home/ga/Pictures /home/ga/Documents

# Open terminal for the user (ffmpeg operations are likely needed)
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Videos &" 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="