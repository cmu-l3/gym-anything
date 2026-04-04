#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Frame-by-Frame Tutorial Analysis Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Videos /home/ga/Pictures

# Generate tutorial video with red marker at specific frames
TUTORIAL_VIDEO="/home/ga/Videos/tutorial_sample.mp4"

if [ ! -f "$TUTORIAL_VIDEO" ]; then
    echo "Generating tutorial video with red marker..."
    
    # Generate 15-second video at 30fps (450 frames) with blue gradient background
    # Red square marker (100x100px) appears in center at frames 180-200 (6-6.67 seconds)
    # Using ffmpeg with drawbox filter enabled only for specific frame range
    
    su - ga -c "ffmpeg -y -f lavfi -i 'color=c=0x4a90e2:s=1280x720:d=15:r=30' \
        -vf \"drawbox=x=(iw-100)/2:y=(ih-100)/2:w=100:h=100:color=red:t=fill:enable='between(n,180,200)'\" \
        -c:v libx264 -pix_fmt yuv420p -preset fast \
        '$TUTORIAL_VIDEO' > /tmp/ffmpeg_tutorial_gen.log 2>&1"
    
    if [ $? -eq 0 ] && [ -f "$TUTORIAL_VIDEO" ]; then
        echo "✅ Tutorial video generated successfully"
        ls -lh "$TUTORIAL_VIDEO"
    else
        echo "ERROR: Failed to generate tutorial video"
        cat /tmp/ffmpeg_tutorial_gen.log
        exit 1
    fi
else
    echo "Tutorial video already exists"
fi

# Verify video was created with correct properties
if ! command -v ffprobe &> /dev/null; then
    echo "WARNING: ffprobe not available, skipping video verification"
else
    DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TUTORIAL_VIDEO" 2>/dev/null || echo "0")
    if (( $(echo "$DURATION > 10" | bc -l) )); then
        echo "✅ Video duration verified: ${DURATION}s"
    else
        echo "WARNING: Video duration seems incorrect: ${DURATION}s"
    fi
fi

# Clear any old snapshots
rm -f /home/ga/Pictures/vlc/vlc-snap*.png 2>/dev/null || true

# Launch VLC with the tutorial video
echo "Launching VLC with tutorial video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$TUTORIAL_VIDEO' > /tmp/vlc_frame_step_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_frame_step_task.log
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

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Brief play to initialize video output (required for frame stepping to work properly)
echo "Initializing video output..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

# Seek to beginning to ensure consistent start position
echo "Resetting to start..."
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 0.5

echo "=== Frame-by-Frame Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is paused at the start of a tutorial video"
echo "  2. Navigate to approximately 5-7 seconds (where target frame is located)"
echo "  3. Pause the video if not already paused (Space)"
echo "  4. Use frame-by-frame stepping: press 'e' to advance one frame"
echo "  5. Look for a RED SQUARE (100x100px) in the center of the frame"
echo "  6. When you see the red square centered, press Shift+S to capture snapshot"
echo ""
echo "Hint: The marker appears around 6-7 seconds into the video"
echo "Hint: Use Right Arrow or Shift+Right to quickly seek to ~6 seconds first"