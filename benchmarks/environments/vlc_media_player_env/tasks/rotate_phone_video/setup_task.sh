#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Rotate Phone Video Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Define paths
VIDEO_DIR="/home/ga/Videos"
VIDEO_FILE="$VIDEO_DIR/sideways_concert.mp4"
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"

# Ensure video directory exists
mkdir -p "$VIDEO_DIR"

# Create a video with clear orientation markers
echo "Creating test video with orientation markers..."

# Generate a portrait-mode video (720x1280) with clear orientation indicators
# This simulates a phone video recorded in portrait mode
ffmpeg -y -f lavfi -i color=c=blue:s=720x1280:d=15:r=24 \
    -vf "drawtext=text='TOP':fontsize=100:fontcolor=white:x=(w-text_w)/2:y=80:box=1:boxcolor=black@0.5:boxborderw=10,\
         drawtext=text='Concert Video':fontsize=60:fontcolor=yellow:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='BOTTOM':fontsize=100:fontcolor=white:x=(w-text_w)/2:y=h-180:box=1:boxcolor=black@0.5:boxborderw=10,\
         drawtext=text='LEFT':fontsize=60:fontcolor=red:x=50:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5,\
         drawtext=text='RIGHT':fontsize=60:fontcolor=green:x=w-text_w-50:y=(h-text_h)/2:box=1:boxcolor=black@0.5:boxborderw=5" \
    -c:v libx264 -pix_fmt yuv420p -preset fast -crf 22 "$VIDEO_FILE.tmp" \
    > /tmp/vlc_rotate_setup.log 2>&1

if [ ! -f "$VIDEO_FILE.tmp" ]; then
    echo "ERROR: Failed to create base video"
    cat /tmp/vlc_rotate_setup.log
    exit 1
fi

# Rotate video 90 degrees clockwise (transpose=1) to simulate sideways recording
# This makes it so the video needs to be rotated counter-clockwise to view correctly
echo "Rotating video 90° clockwise to simulate sideways recording..."
ffmpeg -y -i "$VIDEO_FILE.tmp" -vf "transpose=1" -c:v libx264 -crf 22 -preset fast "$VIDEO_FILE" \
    >> /tmp/vlc_rotate_setup.log 2>&1

# Clean up temporary file
rm -f "$VIDEO_FILE.tmp"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to create rotated video"
    cat /tmp/vlc_rotate_setup.log
    exit 1
fi

echo "✅ Video created and rotated: $VIDEO_FILE"
ls -lh "$VIDEO_FILE"

# Clear any existing VLC video filter settings related to transform
echo "Clearing existing transform settings from VLC config..."
if [ -f "$VLC_CONFIG" ]; then
    # Remove transform-related settings
    sed -i '/^video-filter=.*transform/d' "$VLC_CONFIG"
    sed -i '/^vout-filter=.*transform/d' "$VLC_CONFIG"
    sed -i '/^transform-type=/d' "$VLC_CONFIG"
    sed -i '/^video-filter=/d' "$VLC_CONFIG"
    sed -i '/^vout-filter=/d' "$VLC_CONFIG"
    echo "Transform settings cleared"
fi

# Ensure VLC is not running
pkill -9 vlc 2>/dev/null || true
sleep 1

# Set proper permissions
chown -R ga:ga "$VIDEO_DIR"
chmod 644 "$VIDEO_FILE"

# Launch VLC with the sideways video
echo "Launching VLC with sideways video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$VIDEO_FILE' > /tmp/vlc_rotate_task.log 2>&1 &"

# Wait for VLC to start
if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_rotate_task.log
    exit 1
fi

# Wait for window to appear
if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_rotate_task.log
    exit 1
fi

# Click on center of screen to select desktop (standard practice)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (ID: $wid)"
fi

# Wait for video to fully load
sleep 2

echo "=== Rotate Phone Video Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  The video at $VIDEO_FILE is playing sideways (rotated 90° clockwise)."
echo "  You can see 'TOP' text should be at the top but is currently on the side."
echo ""
echo "  To fix the orientation:"
echo "  1. Open Tools → Effects and Filters (or press Ctrl+E)"
echo "  2. Click on 'Video Effects' tab"
echo "  3. Click on 'Geometry' sub-tab"
echo "  4. Check the 'Transform' checkbox to enable it"
echo "  5. From the Transform dropdown, select 'Rotate by 90 degrees'"
echo "     (or 'Rotate by 270 degrees' - both correct the orientation)"
echo "  6. Close the Effects window - the rotation should apply immediately"
echo ""
echo "  The video should now display with 'TOP' at the top."
echo ""