#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stabilize Shaky Video Task ==="

kill_vlc ga
sleep 1

# Create shaky video file using ffmpeg
VIDEOS_DIR="/home/ga/Videos"
SHAKY_VIDEO="$VIDEOS_DIR/shaky_phone_video.mp4"

echo "Creating shaky video file..."
mkdir -p "$VIDEOS_DIR"

# Generate video with simulated camera shake using ffmpeg
# Use transform filter to create realistic handheld shake
# Creates a 15-second video with sine wave rotation to simulate shake
if [ ! -f "$SHAKY_VIDEO" ]; then
    ffmpeg -f lavfi -i testsrc=duration=15:size=1280x720:rate=30 \
        -vf "rotate='sin(t*2)*0.08':fillcolor=black,crop=iw-40:ih-40" \
        -c:v libx264 -pix_fmt yuv420p -y "$SHAKY_VIDEO" \
        > /tmp/setup_shaky_video.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create shaky video"
        cat /tmp/setup_shaky_video.log
        exit 1
    fi
    
    echo "✅ Shaky video created: $SHAKY_VIDEO"
else
    echo "✅ Shaky video already exists: $SHAKY_VIDEO"
fi

chown ga:ga "$SHAKY_VIDEO"

# Reset VLC video filter settings to ensure clean state
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

if [ -f "$VLC_RC" ]; then
    # Remove any existing video filter settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^transform-type=/d' "$VLC_RC"
    sed -i '/^vout-filter=/d' "$VLC_RC"
    sed -i '/^video-splitter=/d' "$VLC_RC"
    echo "VLC video filters reset"
fi

# Launch VLC with shaky video and loop enabled
echo "Launching VLC with shaky video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$SHAKY_VIDEO' > /tmp/vlc_stabilize_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_stabilize_task.log
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

# Wait for video to start playing
sleep 2

echo "=== Stabilize Shaky Video Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a shaky video (simulated phone recording)"
echo "  2. Enable stabilization filter:"
echo "     - Open Tools → Effects and Filters (Ctrl+E)"
echo "     - Click 'Video Effects' tab"
echo "     - Click 'Geometry' sub-tab"
echo "     - Enable 'Transform' checkbox"
echo "     OR"
echo "     - Look for any stabilization/motion smoothing filter"
echo "  3. Close the dialog - settings will persist automatically"
echo "  4. The filter will smooth out the camera shake in real-time"