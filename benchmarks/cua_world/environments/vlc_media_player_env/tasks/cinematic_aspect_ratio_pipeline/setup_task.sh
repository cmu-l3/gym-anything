#!/bin/bash
# Setup script for cinematic_aspect_ratio_pipeline task
set -e

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

echo "=== Setting up Cinematic Aspect Ratio task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Videos/aspect_ratios
chown -R ga:ga /home/ga/Videos/aspect_ratios

# Attempt to download a real 1080p source video (Blender trailer)
echo "Preparing source video..."
DOWNLOAD_SUCCESS=false
if wget -qO /tmp/trailer_1080p.mov "https://download.blender.org/peach/trailer/trailer_1080p.mov"; then
    echo "Downloaded official Blender trailer, trimming to 60s..."
    if ffmpeg -y -i /tmp/trailer_1080p.mov -t 60 -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p -c:a aac -b:a 128k -ac 2 /home/ga/Videos/source_clip.mp4 2>/dev/null; then
        DOWNLOAD_SUCCESS=true
    fi
    rm -f /tmp/trailer_1080p.mov
fi

# Fallback to testsrc2 standard pattern if download fails
if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo "Using industry-standard testsrc2 pattern as fallback..."
    ffmpeg -y \
      -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=60" \
      -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=60" \
      -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
      -c:a aac -b:a 128k -ac 2 \
      /home/ga/Videos/source_clip.mp4 2>/dev/null
fi

chown ga:ga /home/ga/Videos/source_clip.mp4

# Start VLC with the source video
echo "Launching VLC..."
if ! pgrep -f "vlc" > /dev/null; then
    su - ga -c "DISPLAY=:1 vlc /home/ga/Videos/source_clip.mp4 &"
    
    # Wait for VLC window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "vlc"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus VLC
DISPLAY=:1 wmctrl -r "VLC media player" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "VLC media player" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="