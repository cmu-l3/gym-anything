#!/bin/bash
# Setup script for museum_kiosk_exhibit_standardization task
set -e

echo "=== Setting up Museum Kiosk Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/raw_exhibit
mkdir -p /home/ga/Videos/kiosk_ready
mkdir -p /home/ga/Pictures
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Documents

# 1. Create a transparent museum logo (200x200)
echo "Generating museum logo..."
# Using ImageMagick to create a realistic transparent logo
convert -size 200x200 xc:transparent \
  -fill "#004488" -draw "circle 100,100 100,20" \
  -fill white -font DejaVu-Sans-Bold -pointsize 32 -gravity center -annotate +0+0 "MUSEUM\nOCEAN" \
  /home/ga/Pictures/museum_logo.png 2>/dev/null || \
  ffmpeg -y -f lavfi -i color=c=blue@0.5:s=200x200 -frames:v 1 /home/ga/Pictures/museum_logo.png 2>/dev/null

# 2. Prepare raw media files (Use real CC clips from W3C/Blender, fallback to lavfi if offline)
echo "Downloading/Generating raw media..."

# File 1: coral_reef.avi (720p, MPEG4)
if ! wget -q -O /tmp/raw1.mp4 "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4" 2>/dev/null; then
    ffmpeg -y -f lavfi -i mandelbrot=size=1280x720:rate=30 -t 5 /tmp/raw1.mp4 2>/dev/null
fi
ffmpeg -y -i /tmp/raw1.mp4 -s 1280x720 -c:v mpeg4 -q:v 5 -c:a mp3 -t 5 /home/ga/Videos/raw_exhibit/coral_reef.avi 2>/dev/null

# File 2: deep_sea_vent.mov (4K, ProRes/MJPEG simulation)
if ! wget -q -O /tmp/raw2.mp4 "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4" 2>/dev/null; then
    ffmpeg -y -f lavfi -i cellauto=size=1920x1080:rate=24 -t 5 /tmp/raw2.mp4 2>/dev/null
fi
ffmpeg -y -i /tmp/raw2.mp4 -s 3840x2160 -c:v mjpeg -q:v 5 -an -t 5 /home/ga/Videos/raw_exhibit/deep_sea_vent.mov 2>/dev/null

# File 3: kelp_forest.mp4 (1080p, 60fps)
if ! wget -q -O /tmp/raw3.mp4 "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4" 2>/dev/null; then
    ffmpeg -y -f lavfi -i rgbtestsrc=size=1920x1080:rate=60 -t 5 /tmp/raw3.mp4 2>/dev/null
fi
ffmpeg -y -i /tmp/raw3.mp4 -s 1920x1080 -r 60 -c:v libx264 -preset ultrafast -c:a aac -t 5 /home/ga/Videos/raw_exhibit/kelp_forest.mp4 2>/dev/null

# Clean up temp
rm -f /tmp/raw1.mp4 /tmp/raw2.mp4 /tmp/raw3.mp4

# 3. Create the Kiosk Brief
cat > /home/ga/Documents/kiosk_brief.txt << 'EOF'
=== DEEP OCEANS EXHIBIT: AV DEPLOYMENT BRIEF ===

1. VIDEO STANDARDIZATION
Source files in ~/Videos/raw_exhibit/ are a mess. Transcode all three to:
- Resolution: 1920x1080 exactly
- Video Codec: H.264 (AVC)
- Audio Codec: AAC
- Container: MP4
- Save to: ~/Videos/kiosk_ready/
- Names: exhibit_01.mp4, exhibit_02.mp4, exhibit_03.mp4

2. BRANDING
Burn the museum logo (~/Pictures/museum_logo.png) permanently into the bottom-right corner of the video stream during transcoding.

3. PLAYLIST
Create an XSPF playlist named 'ocean_loop.xspf' in the kiosk_ready folder. It must contain the 3 exhibit files in numerical order.

4. AUTOMATION SCRIPT
Create an executable bash script at ~/Desktop/start_kiosk.sh. It must:
- Launch VLC playing the ocean_loop.xspf playlist
- Run in fullscreen
- Loop endlessly
- Disable the On-Screen Display (OSD) entirely
- Disable the video title popup text
EOF

# Set permissions
chown -R ga:ga /home/ga/Videos /home/ga/Pictures /home/ga/Desktop /home/ga/Documents
chmod +x /home/ga/Pictures/museum_logo.png 2>/dev/null || true

# Kill any running VLC instances
pkill -u ga -f vlc || true

# Launch VLC (empty) to ensure UI is visible for the agent
su - ga -c "DISPLAY=:1 vlc &" 2>/dev/null || true
sleep 3

# Maximize VLC window
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="