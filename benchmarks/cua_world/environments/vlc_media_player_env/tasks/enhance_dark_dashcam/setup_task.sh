#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enhance Dark Dashcam Task ==="

kill_vlc ga
sleep 1

# Create darkened dashcam video
SOURCE_VIDEO="/home/ga/Videos/sample_video.mp4"
DARK_VIDEO="/home/ga/Videos/dashcam_dark.mp4"

# Check if source video exists
if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: Source video not found: $SOURCE_VIDEO"
    exit 1
fi

echo "Creating darkened dashcam video..."
# Use ffmpeg to significantly darken the video (reduce brightness and contrast)
# eq filter: brightness=-0.15 (reduce by ~40%), contrast=0.5 (reduce dynamic range)
if ! ffmpeg -i "$SOURCE_VIDEO" -vf "eq=brightness=-0.15:contrast=0.5:saturation=0.8" \
     -c:v libx264 -preset ultrafast -crf 23 -c:a copy \
     "$DARK_VIDEO" -y > /tmp/ffmpeg_darken.log 2>&1; then
    echo "ERROR: Failed to create dark video"
    cat /tmp/ffmpeg_darken.log
    exit 1
fi

chown ga:ga "$DARK_VIDEO"
echo "✅ Dark video created: $DARK_VIDEO"

# Create reference directories
mkdir -p /home/ga/Pictures/vlc
chown ga:ga /home/ga/Pictures/vlc

# Reset VLC config to ensure no effects are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing video adjustment settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^brightness=/d' "$VLC_RC"
    sed -i '/^contrast=/d' "$VLC_RC"
    sed -i '/^gamma=/d' "$VLC_RC"
    sed -i '/^hue=/d' "$VLC_RC"
    sed -i '/^saturation=/d' "$VLC_RC"
    sed -i '/^adjust-enabled=/d' "$VLC_RC"
    echo "Effects reset to defaults"
fi

# Take reference snapshot of dark video for verification
echo "Creating reference snapshot of dark video..."
ffmpeg -i "$DARK_VIDEO" -ss 00:00:03 -vframes 1 \
       /home/ga/Pictures/vlc/original_dark_frame.png -y > /dev/null 2>&1 || true
chown ga:ga /home/ga/Pictures/vlc/original_dark_frame.png 2>/dev/null || true

# Launch VLC with the dark video and loop enabled
echo "Launching VLC with dark dashcam video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$DARK_VIDEO' > /tmp/vlc_enhance_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_enhance_task.log
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

# Wait for video to start rendering
sleep 2

echo "=== Enhance Dark Dashcam Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. The video playing is EXTREMELY dark (simulated dashcam footage)"
echo "  2. Open Tools → Effects and Filters (Ctrl+E)"
echo "  3. Go to Video Effects tab"
echo "  4. Enable 'Image adjust' or 'Essential' checkbox"
echo "  5. Adjust sliders to brighten the video:"
echo "     - Brightness: ~1.5-1.8 (increase significantly)"
echo "     - Contrast: ~1.3-1.6 (restore detail)"
echo "     - Gamma: ~1.2-1.5 (optional, lift midtones)"
echo "  6. Monitor video to ensure details become visible"
echo "  7. Close dialog to apply effects"