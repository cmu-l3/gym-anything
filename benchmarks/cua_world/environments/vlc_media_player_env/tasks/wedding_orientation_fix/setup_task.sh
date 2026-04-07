#!/bin/bash
# Setup script for wedding_orientation_fix task
set -e

source /workspace/scripts/task_utils.sh

echo "Setting up wedding_orientation_fix task..."

kill_vlc

# Create required directories
mkdir -p /home/ga/Videos/wedding_raw
mkdir -p /home/ga/Videos/corrected
mkdir -p /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Generate 6 video clips simulating different real-world orientation issues.
# Each clip is exactly 10 seconds long.
echo "Generating raw video clips..."

# Clip 1: Landscape (Correct) - 1280x720
ffmpeg -y -f lavfi -i "color=c=DarkRed:s=1280x720:d=10" -f lavfi -i "sine=f=400:d=10" \
  -vf "drawtext=text='1. CEREMONY':fontsize=60:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-40, drawtext=text='TOP ^':fontsize=80:fontcolor=white:x=(w-tw)/2:y=(h-th)/2+40" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k /home/ga/Videos/wedding_raw/clip_ceremony_01.mp4 2>/dev/null

# Clip 2: Portrait (Rotated 90° CW in pixel data) - Outputs 720x1280 physical frame
ffmpeg -y -f lavfi -i "color=c=DarkGreen:s=1280x720:d=10" -f lavfi -i "sine=f=500:d=10" \
  -vf "drawtext=text='2. VOWS':fontsize=60:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-40, drawtext=text='TOP ^':fontsize=80:fontcolor=white:x=(w-tw)/2:y=(h-th)/2+40, transpose=1" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k /home/ga/Videos/wedding_raw/clip_vows_02.mp4 2>/dev/null

# Clip 3: Landscape (Upside-down pixel data) - Outputs 1280x720 physical frame, inverted pixels
ffmpeg -y -f lavfi -i "color=c=DarkBlue:s=1280x720:d=10" -f lavfi -i "sine=f=600:d=10" \
  -vf "drawtext=text='3. DANCE':fontsize=60:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-40, drawtext=text='TOP ^':fontsize=80:fontcolor=white:x=(w-tw)/2:y=(h-th)/2+40, vflip, hflip" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k /home/ga/Videos/wedding_raw/clip_dance_03.mp4 2>/dev/null

# Clip 4: Portrait (Rotated 90° CCW in pixel data) - Outputs 720x1280 physical frame
ffmpeg -y -f lavfi -i "color=c=Goldenrod:s=1280x720:d=10" -f lavfi -i "sine=f=700:d=10" \
  -vf "drawtext=text='4. TOAST':fontsize=60:fontcolor=black:x=(w-tw)/2:y=(h-th)/2-40, drawtext=text='TOP ^':fontsize=80:fontcolor=black:x=(w-tw)/2:y=(h-th)/2+40, transpose=2" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k /home/ga/Videos/wedding_raw/clip_toast_04.mp4 2>/dev/null

# Clip 5: Landscape (Correct) - 1280x720
ffmpeg -y -f lavfi -i "color=c=Purple:s=1280x720:d=10" -f lavfi -i "sine=f=800:d=10" \
  -vf "drawtext=text='5. CAKE':fontsize=60:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-40, drawtext=text='TOP ^':fontsize=80:fontcolor=white:x=(w-tw)/2:y=(h-th)/2+40" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k /home/ga/Videos/wedding_raw/clip_cake_05.mp4 2>/dev/null

# Clip 6: Portrait frame WITH embedded rotation metadata - 720x1280 physical, rotate=90 metadata
ffmpeg -y -f lavfi -i "color=c=DarkCyan:s=1280x720:d=10" -f lavfi -i "sine=f=900:d=10" \
  -vf "drawtext=text='6. EXIT':fontsize=60:fontcolor=white:x=(w-tw)/2:y=(h-th)/2-40, drawtext=text='TOP ^':fontsize=80:fontcolor=white:x=(w-tw)/2:y=(h-th)/2+40, transpose=1" \
  -metadata:s:v:0 rotate=90 -c:v libx264 -preset ultrafast -c:a aac -b:a 128k /home/ga/Videos/wedding_raw/clip_exit_06.mp4 2>/dev/null

# Create the Camera Log document
cat > /home/ga/Documents/camera_log.txt << 'LOGEOF'
=== CAMERA LOG: SMITH-JONES WEDDING ===

We used multiple devices to capture the day. Unfortunately, some guests didn't know how to hold their phones, and the DJ's camera was mounted incorrectly.

Directory: /home/ga/Videos/wedding_raw/
Target Deliverable Format: 1280x720 Landscape

1. clip_ceremony_01.mp4 
   - Source: Main Camera
   - Issue: None. Shot perfectly in 1280x720 landscape.

2. clip_vows_02.mp4
   - Source: Aunt's iPhone
   - Issue: Shot in portrait. Pixels are rotated 90 degrees clockwise. Needs to be rotated counter-clockwise to landscape.

3. clip_dance_03.mp4
   - Source: DJ's GoPro
   - Issue: Mounted upside-down. Pixels are inverted 180 degrees. Needs full 180-degree rotation.

4. clip_toast_04.mp4
   - Source: Uncle's Android
   - Issue: Shot in portrait. Pixels are rotated 90 degrees counter-clockwise. Needs to be rotated clockwise.

5. clip_cake_05.mp4
   - Source: Main Camera
   - Issue: None. Shot perfectly in 1280x720 landscape.

6. clip_exit_06.mp4
   - Source: Guest Phone
   - Issue: Physical frame is portrait (720x1280), but it also contains embedded rotate=90 metadata! Remove the metadata and correct the pixel orientation to normal 1280x720 landscape.

Instructions: 
Fix all 6 clips to be fully upright 1280x720 landscape videos without any rotation metadata. Save them in /home/ga/Videos/corrected/. 
Then, concatenate them sequentially into /home/ga/Videos/wedding_highlight.mp4.
Finally, save a JSON report of your fixes to /home/ga/Documents/shot_correction_log.json.
LOGEOF

chown -R ga:ga /home/ga/Videos /home/ga/Documents

# Launch VLC (empty state)
su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "Setup complete for wedding_orientation_fix task"