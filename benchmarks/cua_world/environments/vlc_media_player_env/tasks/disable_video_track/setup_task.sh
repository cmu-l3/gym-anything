#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Disable Video Track Task ==="

kill_vlc ga
sleep 1

# Ensure video directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Create a test lecture video (30-second simulation with audio)
LECTURE_VIDEO="/home/ga/Videos/lecture_long.mp4"

if [ ! -f "$LECTURE_VIDEO" ]; then
    echo "Creating test lecture video..."
    # Create a simple video with audio narration simulation
    # Using testsrc for video and sine wave for audio
    ffmpeg -y -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
           -f lavfi -i sine=frequency=440:duration=30:sample_rate=44100 \
           -c:v libx264 -preset ultrafast -c:a aac -b:a 128k \
           "$LECTURE_VIDEO" > /tmp/ffmpeg_lecture.log 2>&1
    
    chown ga:ga "$LECTURE_VIDEO"
    echo "✅ Test lecture video created: $LECTURE_VIDEO"
else
    echo "✅ Test lecture video already exists"
fi

# Reset VLC config to ensure video is enabled (default state)
VLC_CONFIG_DIR="/home/ga/.config/vlc"
VLC_RC="$VLC_CONFIG_DIR/vlcrc"

mkdir -p "$VLC_CONFIG_DIR"
chown -R ga:ga "$VLC_CONFIG_DIR"

if [ -f "$VLC_RC" ]; then
    echo "Resetting VLC video settings to defaults..."
    # Remove any video-disabling settings
    sed -i '/^vout=/d' "$VLC_RC"
    sed -i '/^no-video=/d' "$VLC_RC"
    sed -i '/^novideo=/d' "$VLC_RC"
    sed -i '/^video=/d' "$VLC_RC"
    
    # Ensure video is enabled (default)
    echo "# Video enabled (default)" >> "$VLC_RC"
    
    echo "✅ VLC config reset to defaults"
fi

# Launch VLC with default settings
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_disable_video_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_disable_video_task.log
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

sleep 2

echo "=== Disable Video Track Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════"
echo "  SCENARIO: You're on a flight with 15% battery remaining."
echo "  You need to listen to a 3-hour lecture, but watching video"
echo "  will drain your battery in 45 minutes."
echo ""
echo "  GOAL: Disable video rendering to save battery while keeping audio."
echo ""
echo "  STEPS:"
echo "    1. Open Tools → Preferences (or press Ctrl+P)"
echo "    2. Click 'All' at bottom-left (Show settings: All)"
echo "    3. Navigate to Video section in left tree"
echo "    4. Find and DISABLE video output:"
echo "       - Uncheck 'Enable video' checkbox, OR"
echo "       - Set 'Video output module' to 'Disable' or 'Dummy'"
echo "    5. Click 'Save' button"
echo "    6. (Optional) Test by opening the lecture video:"
echo "       /home/ga/Videos/lecture_long.mp4"
echo ""
echo "  VERIFICATION: Your vlcrc config must show video disabled."
echo "════════════════════════════════════════════════════════════"