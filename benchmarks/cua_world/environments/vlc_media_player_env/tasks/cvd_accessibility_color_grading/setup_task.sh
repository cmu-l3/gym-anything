#!/bin/bash
# Setup script for cvd_accessibility_color_grading task
set -e

echo "=== Setting up cvd_accessibility_color_grading task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/accessible_variants
mkdir -p /home/ga/Documents

# Generate the source chemistry titration video (10 seconds, 854x480)
# Uses a grey background with a simulated beaker that changes from green (t=0-5) to red (t=5-10)
# This perfectly simulates a pH indicator reaction that is problematic for red-green color blindness
ffmpeg -y \
  -f lavfi -i "color=c=gray:s=854x480:d=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100:duration=10" \
  -vf "drawtext=text='Chemistry Titration Demo':x=(w-tw)/2:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5, \
       drawbox=x=300:y=150:w=254:h=250:color=green@0.8:t=fill:enable='between(t,0,5)', \
       drawbox=x=300:y=150:w=254:h=250:color=red@0.8:t=fill:enable='between(t,5,10)'" \
  -c:v libx264 -preset fast -pix_fmt yuv420p \
  -c:a aac -b:a 128k \
  /home/ga/Videos/chemistry_titration.mp4 2>/dev/null

# Set correct ownership
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Launch VLC with the source video, but minimized or just open the app so the agent sees it
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
    sleep 3
fi

# Focus VLC
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Capture initial state screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="