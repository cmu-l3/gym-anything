#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Mirror Video Horizontal Task ==="

kill_vlc ga
sleep 1

# Ensure necessary directories exist
VIDEO_DIR="/home/ga/Videos"
TEST_VIDEO="$VIDEO_DIR/mirror_test_video.mp4"
VLC_CONFIG="/home/ga/.config/vlc"

mkdir -p "$VIDEO_DIR"
mkdir -p "$VLC_CONFIG"

# Generate test video with directional text indicators
# This makes it visually obvious whether horizontal flip is applied
echo "Generating test video with directional indicators..."

ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=30 -r 30 \
    -vf "drawtext=text='LEFT':fontsize=120:fontcolor=white:x=100:y=320:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='RIGHT':fontsize=120:fontcolor=white:x=900:y=320:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='↑ ORIGINAL ORIENTATION ↑':fontsize=60:fontcolor=yellow:x=280:y=100:box=1:boxcolor=red@0.3:boxborderw=3" \
    -pix_fmt yuv420p "$TEST_VIDEO" -y > /tmp/mirror_video_gen.log 2>&1

if [ ! -f "$TEST_VIDEO" ]; then
    echo "ERROR: Failed to generate test video"
    cat /tmp/mirror_video_gen.log
    exit 1
fi

echo "✅ Test video generated: $(ls -lh $TEST_VIDEO)"

# Reset VLC configuration to ensure no filters are active
echo "Resetting VLC configuration..."
cat > "$VLC_CONFIG/vlcrc" << 'EOF'
[core]
# Video filter settings - start with none
video-filter=
vout-filter=
transform-type=

# Interface preferences
qt-privacy-ask=0
qt-continue=0
qt-start-minimized=0

# Disable hardware acceleration for consistency
avcodec-hw=none
EOF

chown -R ga:ga "$VLC_CONFIG"
chown -R ga:ga "$VIDEO_DIR"

echo "VLC configuration reset"

# Launch VLC with the test video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$TEST_VIDEO' > /tmp/vlc_mirror_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_mirror_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_mirror_task.log
    exit 1
fi

# Click on center of screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Let video render for a moment
sleep 2

echo "=== Mirror Video Horizontal Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is playing a test video with 'LEFT' and 'RIGHT' text labels"
echo "  2. Apply horizontal flip transformation:"
echo "     a. Open Tools → Effects and Filters (Ctrl+E)"
echo "     b. Go to 'Video Effects' tab"
echo "     c. Click on 'Geometry' sub-tab"
echo "     d. Check the 'Transform' checkbox"
echo "     e. Select 'Flip horizontally' from the dropdown"
echo "     f. Close the dialog"
echo "  3. After applying, 'LEFT' should appear on the right side"
echo "  4. The transformation should persist when you replay the video"
echo ""
echo "Video file: $TEST_VIDEO"