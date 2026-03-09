#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Correct Color Space Task ==="

kill_vlc ga
sleep 1

# Ensure video directory exists
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate test video with incorrect colors (greenish tint, washed out)
OUTPUT_VIDEO="/home/ga/Videos/client_footage_raw.mp4"

echo "Generating test video with incorrect color space..."

# Create a 30-second test video with color patterns and intentionally wrong colors
# Apply greenish tint (hue shift) and reduce gamma/contrast to simulate wrong color space
ffmpeg -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 \
    -vf "hue=h=30:s=0.7,eq=gamma=0.7:contrast=0.8:brightness=0.05" \
    -c:v libx264 -preset fast -crf 18 \
    -pix_fmt yuv420p \
    "$OUTPUT_VIDEO" -y 2>/tmp/vlc_setup_color.log

if [ ! -f "$OUTPUT_VIDEO" ]; then
    echo "ERROR: Failed to generate test video"
    cat /tmp/vlc_setup_color.log
    exit 1
fi

echo "✅ Test video created: $OUTPUT_VIDEO"
ls -lh "$OUTPUT_VIDEO"

# Ensure snapshot directory exists
mkdir -p /home/ga/Pictures/vlc
chown ga:ga /home/ga/Pictures/vlc

# Reset VLC config to ensure no color adjustments are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing color adjustment settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^adjust-/d' "$VLC_RC"
    echo "Color adjustment settings reset"
fi

# Launch VLC with the incorrectly colored video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$OUTPUT_VIDEO' > /tmp/vlc_colorspace_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_colorspace_task.log
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

# Let video play for a moment so user can see the incorrect colors
sleep 2

echo "=== Correct Color Space Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video is playing with incorrect colors (washed out, greenish)"
echo "  2. Open Tools -> Effects and Filters (Ctrl+E)"
echo "  3. Go to Video Effects tab -> Essential sub-tab"
echo "  4. Enable 'Image adjust' checkbox"
echo "  5. Adjust Gamma to ~1.3-1.5 (restore black levels)"
echo "  6. Adjust Hue to ~-20 to -30 degrees (remove green tint)"
echo "  7. Optionally adjust Saturation to ~1.1-1.2"
echo "  8. Close dialog - settings should auto-save"