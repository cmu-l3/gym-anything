#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Frame Analysis Export Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures
mkdir -p /tmp/vlc_frame_task_setup

# Set ownership
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Pictures

# Clean up any existing snapshot at target location
rm -f /home/ga/Pictures/analysis_frame.png
rm -f /home/ga/Pictures/vlc-snap*.png

echo "Generating test video with red flash marker..."

OUTPUT_VIDEO="/home/ga/Videos/analysis_target.mp4"

# Check if ffmpeg is available
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg not found"
    exit 1
fi

# Generate base video (120 seconds, 30fps, 1280x720, blue background)
# Add a sine wave audio track to make it more realistic
echo "Creating base video (2 minutes, 1280x720, 30fps)..."
ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=120:r=30 \
       -f lavfi -i "sine=frequency=440:duration=120" \
       -c:v libx264 -preset ultrafast -crf 23 \
       -c:a aac -b:a 128k \
       -pix_fmt yuv420p \
       -y /tmp/vlc_frame_task_setup/base_video.mp4 \
       > /tmp/vlc_frame_task_setup/ffmpeg_base.log 2>&1

if [ ! -f /tmp/vlc_frame_task_setup/base_video.mp4 ]; then
    echo "ERROR: Failed to generate base video"
    cat /tmp/vlc_frame_task_setup/ffmpeg_base.log
    exit 1
fi

echo "Adding red flash at frame 2250 (timestamp 75.0s = 1:15)..."

# Create red flash overlay at specific frames
# Flash appears at frames 2250, 2251, 2252 (3 frames total)
# The drawbox filter will draw a 200x200 red square in the center
ffmpeg -i /tmp/vlc_frame_task_setup/base_video.mp4 \
       -vf "drawbox=x=(iw-200)/2:y=(ih-200)/2:w=200:h=200:color=red@1.0:t=fill:enable='between(n,2250,2252)'" \
       -c:v libx264 -preset ultrafast -crf 18 \
       -c:a copy \
       -y "$OUTPUT_VIDEO" \
       > /tmp/vlc_frame_task_setup/ffmpeg_flash.log 2>&1

# Verify video was created
if [ ! -f "$OUTPUT_VIDEO" ]; then
    echo "ERROR: Failed to generate test video with red flash"
    cat /tmp/vlc_frame_task_setup/ffmpeg_flash.log
    exit 1
fi

# Get and log video info
echo "Video created successfully. Properties:"
ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,duration,r_frame_rate,nb_frames \
        -of default=noprint_wrappers=1 "$OUTPUT_VIDEO" \
        2>/dev/null | tee /tmp/vlc_frame_task_setup/video_info.txt || true

# Set ownership
chown ga:ga "$OUTPUT_VIDEO"

# Launch VLC with the test video, paused at start
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$OUTPUT_VIDEO' > /tmp/vlc_frame_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_frame_task.log
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

# Wait for VLC to fully initialize
sleep 2

echo "=== Frame Analysis Export Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video location: $OUTPUT_VIDEO"
echo "  2. Red flash appears at timestamp 1:15 (75 seconds)"
echo "  3. Flash duration: 3 frames (~100ms at 30fps)"
echo "  4. Steps to complete:"
echo "     a. Navigate to approximately 1:15 using timeline/seek"
echo "     b. Enable Advanced Controls if needed (View → Advanced Controls)"
echo "     c. Use 'e' key for frame-by-frame forward navigation"
echo "     d. Locate frame with red square in center"
echo "     e. Press Shift+S to capture snapshot"
echo "     f. Rename snapshot to: /home/ga/Pictures/analysis_frame.png"
echo ""
echo "  Alternative methods:"
echo "  - Jump to time: Ctrl+T, enter '1:15'"
echo "  - Seek forward: Shift+Right (5s jumps)"
echo "  - Frame-by-frame: 'e' key or Advanced Controls button"