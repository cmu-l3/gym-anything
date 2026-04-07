#!/bin/bash
# Setup script for digital_billboard_legacy_compliance task
set -e

echo "=== Setting up DOOH Legacy Compliance task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state
pkill -u ga -f vlc || true

# Create required directories
mkdir -p /home/ga/Videos/dooh_delivery/proofs
mkdir -p /home/ga/Documents

# Generate the master promo video (30 seconds, 1920x1080, 60fps, H.264, AAC)
echo "Generating master promo video..."
ffmpeg -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=30" \
  -vf "drawtext=text='DOOH MASTER PROMO':x=(w-tw)/2:y=(h-th)/2-50:fontsize=72:fontcolor=white:box=1:boxcolor=black@0.5,drawtext=text='%{pts\:hms}':x=(w-tw)/2:y=(h-th)/2+50:fontsize=48:fontcolor=white:box=1:boxcolor=black@0.5" \
  -c:v libx264 -preset ultrafast -b:v 5M \
  -c:a aac -b:a 192k -ac 2 \
  /home/ga/Videos/client_master_promo.mp4 2>/dev/null

# Record the original master's details for verification
stat -c %Y /home/ga/Videos/client_master_promo.mp4 > /tmp/master_mtime.txt

# Set permissions
chown -R ga:ga /home/ga/Videos/dooh_delivery
chown -R ga:ga /home/ga/Documents
chown ga:ga /home/ga/Videos/client_master_promo.mp4

# Launch VLC in the background (no file loaded) to simulate a ready environment
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 3

# Maximize VLC window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot of the environment
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="