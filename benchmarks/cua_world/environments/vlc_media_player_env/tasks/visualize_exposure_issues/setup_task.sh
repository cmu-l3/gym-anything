#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Visualize Exposure Issues Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Pictures/vlc

# Create wedding footage with exposure extremes
echo "Creating wedding footage with mixed exposure..."

WEDDING_VIDEO="/home/ga/Videos/wedding_footage.mp4"

# Generate test video with clear exposure zones:
# - Top-left: Blown highlights (white)
# - Top-right: Crushed blacks (black)
# - Bottom-left: Proper exposure (gray)
# - Bottom-right: Mid-range (light gray)
# Add text labels and some texture/noise to make it realistic

ffmpeg -y -f lavfi -i color=c=white:s=960x540:d=15:r=30 \
  -f lavfi -i color=c=black:s=960x540:d=15:r=30 \
  -f lavfi -i color=c=gray:s=960x540:d=15:r=30 \
  -f lavfi -i color=c=lightgray:s=960x540:d=15:r=30 \
  -filter_complex "\
    [0:v]noise=alls=15:allf=t+u,drawtext=text='BLOWN HIGHLIGHTS':x=(w-text_w)/2:y=50:fontsize=36:fontcolor=black:box=1:boxcolor=white@0.5:boxborderw=5[tl]; \
    [1:v]noise=alls=15:allf=t+u,drawtext=text='CRUSHED BLACKS':x=(w-text_w)/2:y=50:fontsize=36:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=5[tr]; \
    [2:v]noise=alls=20:allf=t+u,drawtext=text='PROPER EXPOSURE':x=(w-text_w)/2:y=450:fontsize=32:fontcolor=white:box=1:boxcolor=gray@0.5:boxborderw=5[bl]; \
    [3:v]noise=alls=20:allf=t+u,drawtext=text='MID-RANGE':x=(w-text_w)/2:y=450:fontsize=32:fontcolor=black:box=1:boxcolor=lightgray@0.5:boxborderw=5[br]; \
    [tl][tr]hstack=inputs=2[top]; \
    [bl][br]hstack=inputs=2[bottom]; \
    [top][bottom]vstack=inputs=2,scale=1920:1080[final]" \
  -map "[final]" -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p \
  -t 15 "$WEDDING_VIDEO" > /tmp/ffmpeg_wedding.log 2>&1

if [ ! -f "$WEDDING_VIDEO" ]; then
    echo "ERROR: Failed to create wedding footage"
    cat /tmp/ffmpeg_wedding.log
    exit 1
fi

echo "✅ Wedding footage created: $WEDDING_VIDEO"
ls -lh "$WEDDING_VIDEO"

# Reset VLC config to ensure no video filters are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing video filter settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^vout-filter=/d' "$VLC_RC"
    sed -i '/^gradient-mode=/d' "$VLC_RC"
    sed -i '/^gradient-type=/d' "$VLC_RC"
    sed -i '/^extract-component=/d' "$VLC_RC"
    sed -i '/^sepia-intensity=/d' "$VLC_RC"
    sed -i '/^posterize-level=/d' "$VLC_RC"
    echo "Video filters reset"
fi

# Launch VLC with the wedding footage
echo "Launching VLC with wedding footage..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$WEDDING_VIDEO' > /tmp/vlc_exposure_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_exposure_task.log
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

# Give video a moment to start rendering
sleep 2

echo "=== Visualize Exposure Issues Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing wedding footage with mixed exposure"
echo "  2. Open Effects and Filters (Tools → Effects and Filters or Ctrl+E)"
echo "  3. Go to Video Effects tab"
echo "  4. Enable a visualization filter:"
echo "     - Gradient: Shows edges and transitions (good for exposure)"
echo "     - Extract: Highlights specific color/brightness ranges"
echo "     - Threshold: Binary black/white based on brightness"
echo "     - Posterize: Reduces tones, shows banding"
echo "  5. Observe filtered video showing exposure problems"
echo "  6. Take snapshot (Shift+S) showing the filtered visualization"
echo "  7. Snapshot will save to /home/ga/Pictures/vlc/"