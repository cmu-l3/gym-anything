#!/bin/bash
echo "=== Setting up Planetarium Stereoscopic Formatting task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure utility scripts are available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Create required directories
mkdir -p /home/ga/Videos/exhibits
mkdir -p /home/ga/Documents
mkdir -p /var/lib/app/ground_truth

# 1. Generate the source Half Side-by-Side (HSBS) 3D video (10 seconds)
# Uses a test pattern, splits it into two halves. 
# Left side gets a red overlay "LEFT EYE", Right side gets a blue overlay "RIGHT EYE"
echo "Generating HSBS source video..."
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=10" \
  -vf "split[l][r];[l]drawtext=text='LEFT EYE':x=(w-tw)/2:y=h/2:fontsize=120:fontcolor=white:box=1:boxcolor=red@0.6,scale=960:1080[l_sq];[r]drawtext=text='RIGHT EYE':x=(w-tw)/2:y=h/2:fontsize=120:fontcolor=white:box=1:boxcolor=blue@0.6,scale=960:1080[r_sq];[l_sq][r_sq]hstack=inputs=2" \
  -c:v libx264 -preset ultrafast -c:a aac -b:a 128k -ac 2 -ar 44100 /home/ga/Videos/mars_rover_hsbs.mp4 2>/dev/null

# 2. Generate Ground Truth videos (hidden from agent) for verification using SSIM
echo "Generating Ground Truth for verification..."
# GT Left (Crop left half 960x1080, stretch to 1920x1080, keep audio)
ffmpeg -y -i /home/ga/Videos/mars_rover_hsbs.mp4 -vf "crop=960:1080:0:0,scale=1920:1080" -c:a copy /var/lib/app/ground_truth/gt_lobby_2d.mp4 2>/dev/null

# GT Right (Crop right half 960x1080 starting at x=960, stretch to 1920x1080, drop audio)
ffmpeg -y -i /home/ga/Videos/mars_rover_hsbs.mp4 -vf "crop=960:1080:960:0,scale=1920:1080" -an /var/lib/app/ground_truth/gt_dome_right.mp4 2>/dev/null

# GT Anaglyph (Red/Cyan Dubois)
ffmpeg -y -i /home/ga/Videos/mars_rover_hsbs.mp4 -vf "stereo3d=sbsl:arcd" -c:a copy /var/lib/app/ground_truth/gt_classroom_anaglyph.mp4 2>/dev/null

# Set ownership
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Launch VLC with no media to establish the environment state
su - ga -c "DISPLAY=:1 vlc &" 2>/dev/null || true

# Wait for VLC window
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "VLC media player"; then
        break
    fi
    sleep 1
done

# Maximize VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="