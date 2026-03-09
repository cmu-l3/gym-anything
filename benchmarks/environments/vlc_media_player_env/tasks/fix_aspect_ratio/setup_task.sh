#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Aspect Ratio Task ==="

kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos
mkdir -p /tmp/vlc_task_logs

# Generate a 4:3 aspect ratio video (640x480 resolution)
# This represents old VHS/camcorder footage
echo "Generating 4:3 test video (simulating old family video)..."

VIDEO_PATH="/home/ga/Videos/old_family_video.mp4"

# Create a test pattern video with 4:3 aspect ratio
# Using testsrc2 which has better visual patterns to show stretching
ffmpeg -f lavfi -i testsrc2=duration=30:size=640x480:rate=30 \
    -f lavfi -i sine=frequency=440:duration=30 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -aspect 4:3 \
    -y "$VIDEO_PATH" \
    2>&1 | tee /tmp/vlc_task_logs/video_generation.log

# Verify video was created
if [ ! -f "$VIDEO_PATH" ]; then
    echo "ERROR: Failed to generate test video"
    exit 1
fi

echo "Video created: $VIDEO_PATH"
ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,display_aspect_ratio \
    -of default=noprint_wrappers=1 \
    "$VIDEO_PATH" | tee /tmp/vlc_task_logs/original_video_info.txt

# Reset VLC config to ensure clean state
# Remove any existing aspect ratio preferences to force default behavior
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"

if [ -f "$VLC_RC" ]; then
    # Remove any aspect ratio settings
    sed -i '/^aspect-ratio=/d' "$VLC_RC"
    sed -i '/^monitor-par=/d' "$VLC_RC"
    sed -i '/^crop=/d' "$VLC_RC"
    echo "Cleared existing aspect ratio settings from VLC config"
fi

# Set permissions
chown -R ga:ga /home/ga/Videos
chown -R ga:ga "$VLC_CONFIG_DIR"
chmod -R 755 /home/ga/Videos

# Launch VLC with the video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$VIDEO_PATH' > /tmp/vlc_aspect_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_aspect_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Fix Aspect Ratio Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video is playing: /home/ga/Videos/old_family_video.mp4"
echo "  2. The video content is 4:3 but may appear stretched"
echo "  3. Fix the aspect ratio by:"
echo "     - Open Video menu → Aspect Ratio → 4:3"
echo "     - Or press 'A' to cycle through aspect ratios until 4:3 is selected"
echo "  4. The video should display with correct proportions (pillarboxed)"
echo ""
echo "Target: Set aspect ratio to 4:3"