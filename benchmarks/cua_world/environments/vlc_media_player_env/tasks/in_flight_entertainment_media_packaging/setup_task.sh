#!/bin/bash
echo "=== Setting up IFE Media Packaging task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean slate
kill_vlc 2>/dev/null || true

# Create required directories
mkdir -p /home/ga/Videos/Source
mkdir -p /home/ga/Videos/IFE_Ready
mkdir -p /home/ga/Documents

# Clean previous runs if any
rm -rf /home/ga/Videos/Source/*
rm -rf /home/ga/Videos/IFE_Ready/*
rm -f /home/ga/Documents/ife_manifest.json
rm -f /home/ga/Documents/compliance_overlay.srt

echo "Generating source media..."

# Source file 1: promo_destinations.mp4 (1080p, stereo, 48kHz)
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k -ac 2 -ar 48000 \
  /home/ga/Videos/Source/promo_destinations.mp4 2>/dev/null

# Source file 2: promo_rewards.mkv (720p, stereo, 48kHz)
ffmpeg -y -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=10" \
  -f lavfi -i "sine=frequency=523:sample_rate=48000:duration=10" \
  -c:v libx264 -preset ultrafast -b:v 1.5M \
  -c:a aac -b:a 128k -ac 2 -ar 48000 \
  /home/ga/Videos/Source/promo_rewards.mkv 2>/dev/null

# Source file 3: promo_safety.mp4 (1080p, stereo, 48kHz)
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=659:sample_rate=48000:duration=10" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  -c:a aac -b:a 128k -ac 2 -ar 48000 \
  /home/ga/Videos/Source/promo_safety.mp4 2>/dev/null

echo "Generating subtitle file..."

# Create compliance subtitle file
cat > /home/ga/Documents/compliance_overlay.srt << 'SRTEOF'
1
00:00:00,000 --> 00:00:10,000
Edited for Airline Use
SRTEOF

# Set ownership
chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC into an empty, maximized state
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 4

DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="