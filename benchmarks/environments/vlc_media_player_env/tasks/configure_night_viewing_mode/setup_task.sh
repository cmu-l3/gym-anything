#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Night Viewing Mode Task ==="

kill_vlc ga
sleep 1

# Reset VLC configuration to defaults (remove any existing video adjustments)
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_CONFIG_DIR="/home/ga/.config/vlc"

mkdir -p "$VLC_CONFIG_DIR"

# Remove existing video adjustment settings
if [ -f "$VLC_RC" ]; then
    echo "Removing existing video adjustments..."
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^video-splitter=/d' "$VLC_RC"
    sed -i '/^brightness=/d' "$VLC_RC"
    sed -i '/^gamma=/d' "$VLC_RC"
    sed -i '/^hue=/d' "$VLC_RC"
    sed -i '/^contrast=/d' "$VLC_RC"
    sed -i '/^saturation=/d' "$VLC_RC"
    sed -i '/^adjust-enabled=/d' "$VLC_RC"
else
    # Create minimal config
    cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0
qt-start-minimized=0

[video]
video-on-top=0
snapshot-path=/home/ga/Pictures/vlc
snapshot-format=png

[audio]
audio-volume=256

[core]
loop=0
repeat=0
EOF
fi

chown -R ga:ga "$VLC_CONFIG_DIR"

# Generate test video with bright content (space/sci-fi theme with bright whites and blues)
echo "Generating bright test video for night viewing task..."
VIDEO_FILE="/home/ga/Videos/night_test_video.mp4"

# Create a video with bright colors and some dark scenes to test visibility
ffmpeg -y -f lavfi -i "color=c=white:s=1280x720:d=5,color=c=blue:s=1280x720:d=5,color=c=black:s=1280x720:d=3,color=c=cyan:s=1280x720:d=5,color=c=white:s=1280x720:d=2" \
    -f lavfi -i "sine=frequency=440:duration=20" \
    -vf "concat=n=5:v=1:a=0,format=yuv420p" \
    -c:v libx264 -preset fast -crf 23 -c:a aac -shortest \
    "$VIDEO_FILE" > /tmp/ffmpeg_night_video.log 2>&1 || {
    echo "Warning: Failed to create custom video, using fallback..."
    # Fallback: use existing video if generation fails
    if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
        cp /home/ga/Videos/sample_video.mp4 "$VIDEO_FILE"
    fi
}

chown ga:ga "$VIDEO_FILE" 2>/dev/null || true

echo "Launching VLC with bright test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$VIDEO_FILE' > /tmp/vlc_night_mode_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_night_mode_task.log
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

# Let video play briefly to show bright content
sleep 2

echo "=== Configure Night Viewing Mode Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  Scenario: You're watching this video in bed at midnight in a dark room."
echo "  The bright whites and blues are painfully glaring. Configure VLC to:"
echo ""
echo "  1. Open Tools → Effects and Filters (or press Ctrl+E)"
echo "  2. Go to Video Effects tab"
echo "  3. Click on 'Essential' or 'Adjust' sub-tab"
echo "  4. Enable 'Image adjust' checkbox"
echo "  5. Reduce Brightness slider to ~0.60-0.70 (left from center)"
echo "     OR reduce Gamma slider to ~0.60-0.80"
echo "  6. OPTIONAL: Adjust Hue slightly for warmer tones (reduces blue light)"
echo "  7. Close the dialog - settings should save automatically"
echo ""
echo "  Goal: Make the video darker and warmer, but dark scenes should still be visible"
echo "  Settings must persist after closing VLC"