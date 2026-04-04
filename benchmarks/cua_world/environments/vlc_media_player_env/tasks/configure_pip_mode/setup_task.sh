#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure PiP Mode Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Reset VLC config to ensure always-on-top is initially disabled
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing always-on-top settings
    sed -i '/^video-on-top=/d' "$VLC_RC"
    sed -i '/^qt-video-autoresize=/d' "$VLC_RC"
    echo "Always-on-top setting reset"
fi

# Create a training video if it doesn't exist (30-minute video for realistic scenario)
TRAINING_VIDEO="/home/ga/Videos/training_webinar.mp4"
if [ ! -f "$TRAINING_VIDEO" ]; then
    echo "Creating 30-minute training webinar video..."
    
    # Generate a 30-minute video with test pattern and timestamp overlay
    # This simulates a realistic training video scenario
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=1800:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=440:duration=1800 \
        -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf: \
        text='Training Webinar - %{pts\:hms}': \
        fontcolor=white: fontsize=48: box=1: boxcolor=black@0.5: \
        boxborderw=10: x=(w-text_w)/2: y=50\" \
        -c:v libx264 -preset ultrafast -crf 28 -c:a aac -shortest \
        '$TRAINING_VIDEO' -y > /tmp/ffmpeg_training_video.log 2>&1" || {
        echo "Warning: Failed to create full 30-min video, creating shorter 5-min version..."
        # Fallback: Create 5-minute video if 30-min takes too long
        su - ga -c "ffmpeg -f lavfi -i testsrc=duration=300:size=1280x720:rate=30 \
            -f lavfi -i sine=frequency=440:duration=300 \
            -vf \"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf: \
            text='Training Webinar': fontcolor=white: fontsize=48: \
            x=(w-text_w)/2: y=(h-text_h)/2\" \
            -c:v libx264 -preset ultrafast -crf 28 -c:a aac -shortest \
            '$TRAINING_VIDEO' -y > /tmp/ffmpeg_training_video_short.log 2>&1"
    }
    
    chown ga:ga "$TRAINING_VIDEO"
    echo "Training video created: $TRAINING_VIDEO"
fi

# Verify video exists
if [ ! -f "$TRAINING_VIDEO" ]; then
    echo "ERROR: Training video not found: $TRAINING_VIDEO"
    exit 1
fi

# Launch VLC with the training video in default mode (no always-on-top, normal size)
echo "Launching VLC with training video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none \
    --no-video-title-show \
    --loop \
    '$TRAINING_VIDEO' > /tmp/vlc_pip_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_pip_task.log
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for VLC to fully render
sleep 3

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (ID: $wid)"
fi

# Get initial screen resolution for reference
SCREEN_INFO=$(su - ga -c "DISPLAY=:1 xdpyinfo | awk '/dimensions:/{print \$2}'")
echo "Screen resolution: $SCREEN_INFO"

echo "=== Configure PiP Mode Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing a training webinar video in normal mode"
echo "  2. Enable 'Always on Top' mode:"
echo "     - Via Menu: Video → Always on Top"
echo "     - Or: View → Always on top (depending on VLC version)"
echo "  3. Resize VLC window to compact size (approximately 480x270 pixels)"
echo "     - Drag window edges/corners to resize"
echo "     - Target: ≤ 500x300 pixels"
echo "  4. Position window in screen corner:"
echo "     - Preferred: top-right or bottom-right corner"
echo "     - Drag window title bar to corner"
echo "  5. Ensure video continues playing (not paused)"
echo "  6. Video should remain visible even when clicking other windows"
echo ""
echo "Current screen: $SCREEN_INFO"
echo "Target window size: ≤ 500x300 pixels"
echo "Target position: Screen corner (e.g., top-right)"