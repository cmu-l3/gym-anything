#!/bin/bash
echo "=== Setting up Corporate Signage Overlay Deployment task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure necessary directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# Kill any existing VLC instances to provide a clean slate
pkill -f "vlc" 2>/dev/null || true
sleep 1

# Generate corporate B-roll video (30 seconds, 1920x1080)
echo "Generating B-roll video..."
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=30" \
  -c:v libx264 -preset ultrafast -b:v 2M \
  /home/ga/Videos/corporate_broll.mp4 2>/dev/null

# Generate Corporate Logo (Blue square with white CORP text, 200x200)
echo "Generating corporate logo..."
ffmpeg -y -f lavfi -i "color=c=blue@0.8:s=200x200,drawtext=text='CORP':fontsize=50:fontcolor=white:x=(w-tw)/2:y=(h-th)/2" \
  -frames:v 1 /home/ga/Pictures/corp_logo.png 2>/dev/null

# Generate the ticker text file
echo "Welcome to the 2026 Global Tech Summit - Please sign in at the front desk" > /home/ga/Documents/ticker_text.txt

# Fix permissions
chown -R ga:ga /home/ga/Videos /home/ga/Pictures /home/ga/Documents /home/ga/Desktop

# Take initial screenshot to document clean state
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="