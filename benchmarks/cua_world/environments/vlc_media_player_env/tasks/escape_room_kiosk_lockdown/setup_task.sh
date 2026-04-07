#!/bin/bash
echo "=== Setting up escape_room_kiosk_lockdown task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# Remove any existing outputs from previous runs
rm -f /home/ga/Videos/kiosk_loop.mp4
rm -f /home/ga/Documents/kiosk_vlcrc
rm -f /home/ga/Desktop/start_kiosk.sh
rm -f /tmp/task_result.json
rm -f /tmp/frame_raw.png
rm -f /tmp/frame_kiosk.png
rm -f /tmp/kiosk_vlcrc
rm -f /tmp/start_kiosk.sh

# Generate raw video (1080p, 10s, testsrc2 with audio)
# This provides complex colorful shapes and a gradient, making inversion very easy to verify visually.
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
  -c:v libx264 -preset ultrafast \
  -c:a aac -b:a 128k \
  /home/ga/Videos/briefing_raw.mp4 2>/dev/null

# Make sure permissions are correct
chown -R ga:ga /home/ga/Videos /home/ga/Documents /home/ga/Desktop

# Ensure VLC is not running initially
pkill -f vlc || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="