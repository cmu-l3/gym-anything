#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Correct Aspect Ratio Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure video directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate a test video with INCORRECT aspect ratio metadata
# Create 640x480 content (4:3) but flag it as 16:9 (causing vertical stretch)
echo "Creating test video with incorrect aspect ratio metadata..."

# First check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found, installing..."
    apt-get update && apt-get install -y ffmpeg
fi

# Generate video with test pattern and incorrect aspect ratio
# The video content is 640x480 (4:3) but we set SAR to make DAR 16:9
ffmpeg -f lavfi -i testsrc=duration=20:size=640x480:rate=30 \
    -f lavfi -i sine=frequency=440:duration=20 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -aspect 16:9 \
    -c:a aac -b:a 128k \
    -y /home/ga/Videos/family_reunion_2005.avi 2>/dev/null

# Verify the video was created with wrong aspect ratio
echo "Verifying video has incorrect aspect ratio metadata..."
VIDEO_INFO=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,display_aspect_ratio \
    -of default=noprint_wrappers=1:nokey=1 \
    /home/ga/Videos/family_reunion_2005.avi 2>/dev/null)

echo "Video created: 640x480 with aspect ratio metadata forcing 16:9 display"
echo "This will cause vertical stretching when played"

# Ensure VLC config exists but doesn't have aspect ratio override yet
VLC_CONFIG_DIR="/home/ga/.config/vlc"
mkdir -p "$VLC_CONFIG_DIR"

if [ ! -f "$VLC_CONFIG_DIR/vlcrc" ]; then
    touch "$VLC_CONFIG_DIR/vlcrc"
fi

# Remove any existing aspect ratio override settings
sed -i '/^aspect-ratio=/d' "$VLC_CONFIG_DIR/vlcrc"
sed -i '/^vout-aspect-ratio=/d' "$VLC_CONFIG_DIR/vlcrc"
sed -i '/^custom-aspect-ratios=/d' "$VLC_CONFIG_DIR/vlcrc"
sed -i '/^qt-aspect-ratio=/d' "$VLC_CONFIG_DIR/vlcrc"

# Set ownership
chown -R ga:ga /home/ga/Videos
chown -R ga:ga "$VLC_CONFIG_DIR"

# Launch VLC with the problem video
echo "Launching VLC with incorrectly encoded video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/family_reunion_2005.avi > /tmp/vlc_aspect_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_aspect_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Give it a moment to start playing
sleep 2

echo "=== Correct Aspect Ratio Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Notice the video appears vertically stretched (people look too tall/thin)"
echo "  2. This is because 640x480 content is flagged as 16:9 instead of 4:3"
echo "  3. Configure VLC to force 4:3 aspect ratio:"
echo "     Option A: Video menu → Aspect Ratio → 4:3"
echo "     Option B: Tools → Preferences → Video → Force aspect ratio: 4:3"
echo "     Option C: Right-click video → Video → Aspect Ratio → 4:3"
echo "  4. Verify people now look normal (correct proportions)"
echo ""
echo "Video file: /home/ga/Videos/family_reunion_2005.avi"