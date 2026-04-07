#!/bin/bash
echo "=== Setting up indie_film_adr_screener_prep task ==="

# Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Music
mkdir -p /home/ga/Pictures
mkdir -p /home/ga/Documents/delivery_package

# Generate visual slate (3s) and main action (42s)
ffmpeg -y -f lavfi -i "color=c=black:s=1920x1080:d=3" -vf "drawtext=text='SCENE 42 TAKE 1':fontsize=100:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" -c:v libx264 -preset ultrafast -t 3 /tmp/slate.mp4 2>/dev/null
ffmpeg -y -f lavfi -i "testsrc2=size=1920x1080:rate=24:duration=42" -c:v libx264 -preset ultrafast -t 42 /tmp/action.mp4 2>/dev/null

# Concatenate video parts into a 45s silent video
cat > /tmp/concat.txt << EOF
file '/tmp/slate.mp4'
file '/tmp/action.mp4'
EOF
ffmpeg -y -f concat -safe 0 -i /tmp/concat.txt -c copy /tmp/video_only.mp4 2>/dev/null

# Generate bad camera audio (45s of 440Hz hum to simulate ruined audio)
ffmpeg -y -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=45" -c:a aac -b:a 128k /tmp/bad_audio.m4a 2>/dev/null

# Multiplex into raw camera file
ffmpeg -y -i /tmp/video_only.mp4 -i /tmp/bad_audio.m4a -c copy -map 0:v -map 1:a /home/ga/Videos/scene42_camera_raw.mp4 2>/dev/null

# Generate ADR master (42s of 880Hz tone to simulate studio dialogue)
ffmpeg -y -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=42" -c:a pcm_s16le -ac 2 /home/ga/Music/scene42_adr_master.wav 2>/dev/null

# Generate Studio Watermark image
ffmpeg -y -f lavfi -i "color=c=black@0.0:s=1200x200,format=rgba" -vf "drawtext=text='CONFIDENTIAL SCREENER':fontsize=80:fontcolor=white@0.5:x=(w-text_w)/2:y=(h-text_h)/2" -frames:v 1 /home/ga/Pictures/studio_watermark.png 2>/dev/null

# Set correct permissions
chown -R ga:ga /home/ga/Videos/scene42_camera_raw.mp4
chown -R ga:ga /home/ga/Music/scene42_adr_master.wav
chown -R ga:ga /home/ga/Pictures/studio_watermark.png
chown -R ga:ga /home/ga/Documents/delivery_package

# Clean up temporary generation files
rm -f /tmp/slate.mp4 /tmp/action.mp4 /tmp/concat.txt /tmp/video_only.mp4 /tmp/bad_audio.m4a

# Ensure VLC is running to establish a clean state
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc &"
    sleep 3
fi

# Maximize and focus the VLC window
DISPLAY=:1 wmctrl -r "VLC" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC" 2>/dev/null || true

# Capture the initial environment state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="