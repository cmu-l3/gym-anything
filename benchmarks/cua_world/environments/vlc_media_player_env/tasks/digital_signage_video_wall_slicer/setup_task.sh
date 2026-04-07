#!/bin/bash
echo "=== Setting up Digital Signage Video Wall Slicer Task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Create directories
mkdir -p /home/ga/Videos/signage/wall_slices
mkdir -p /var/lib/app/ground_truth

# Download a real sample video (Big Buck Bunny) or fallback to complex generation
echo "Preparing high-resolution master footage..."
if wget -qO /tmp/src.mp4 "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"; then
    echo "Downloaded official sample data."
    # Scale, crop and pad to exactly 3240x1920, 10 seconds duration
    ffmpeg -y -i /tmp/src.mp4 -vf "scale=3240:1920:force_original_aspect_ratio=increase,crop=3240:1920" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k -t 10 /home/ga/Videos/signage/panorama_master.mp4 2>/dev/null
else
    echo "Download failed. Generating high-complexity fallback footage..."
    # Generate a complex moving fractal with audio if offline
    ffmpeg -y -f lavfi -i "mandelbrot=size=3240x1920:rate=30" -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 10 -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k /home/ga/Videos/signage/panorama_master.mp4 2>/dev/null
fi

# Generate ground truth center frames (hidden from agent)
echo "Generating geometric ground truth slices..."
ffmpeg -y -ss 00:00:05 -i /home/ga/Videos/signage/panorama_master.mp4 -filter:v "crop=1080:1920:0:0" -vframes 1 /var/lib/app/ground_truth/gt_1_left.png 2>/dev/null
ffmpeg -y -ss 00:00:05 -i /home/ga/Videos/signage/panorama_master.mp4 -filter:v "crop=1080:1920:1080:0" -vframes 1 /var/lib/app/ground_truth/gt_2_center.png 2>/dev/null
ffmpeg -y -ss 00:00:05 -i /home/ga/Videos/signage/panorama_master.mp4 -filter:v "crop=1080:1920:2160:0" -vframes 1 /var/lib/app/ground_truth/gt_3_right.png 2>/dev/null

# Secure the ground truth directory
chmod 700 /var/lib/app/ground_truth

# Set permissions for agent
chown -R ga:ga /home/ga/Videos/signage

# Start VLC to set initial state
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc --no-video-title-show &" 2>/dev/null || true
    sleep 3
fi

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="