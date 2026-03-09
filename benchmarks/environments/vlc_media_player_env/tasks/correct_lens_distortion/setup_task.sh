#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Correct Lens Distortion Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Pictures/vlc

# Remove any existing distortion filters from VLC config
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^vout-filter=/d' "$VLC_RC"
    sed -i '/transform/d' "$VLC_RC"
    sed -i '/geometry/d' "$VLC_RC"
    sed -i '/panoramix/d' "$VLC_RC"
    sed -i '/ball/d' "$VLC_RC"
    echo "Cleared existing geometry filters from config"
fi

# Generate test video with barrel distortion
echo "Generating distorted aerial footage..."

# First, create a source video with grid lines and horizon
# This makes distortion very obvious
ffmpeg -f lavfi -i "color=c=skyblue:duration=20:size=1920x1080:rate=30" \
    -vf "drawgrid=width=192:height=108:thickness=3:color=white@0.8,\
         drawbox=x=0:y=520:w=1920:h=40:color=blue@0.9:t=fill,\
         drawtext=text='HORIZON':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=530,\
         drawbox=x=850:y=100:w=220:h=800:color=gray@0.7:t=fill,\
         drawtext=text='BUILDING':fontsize=48:fontcolor=white:x=890:y=400" \
    -pix_fmt yuv420p -c:v libx264 -preset ultrafast -crf 23 \
    /tmp/source_straight.mp4 -y 2>/tmp/ffmpeg_source.log

if [ ! -f /tmp/source_straight.mp4 ]; then
    echo "ERROR: Failed to generate source video"
    cat /tmp/ffmpeg_source.log
    exit 1
fi

# Apply barrel distortion using lenscorrection filter with negative values
# Negative k1 creates barrel distortion (pincushion with positive)
ffmpeg -i /tmp/source_straight.mp4 \
    -vf "lenscorrection=k1=-0.3:k2=-0.1" \
    -c:v libx264 -preset ultrafast -crf 23 \
    /home/ga/Videos/drone_flight_distorted.mp4 -y 2>/tmp/ffmpeg_distort.log

if [ ! -f /home/ga/Videos/drone_flight_distorted.mp4 ]; then
    echo "ERROR: Failed to generate distorted video"
    cat /tmp/ffmpeg_distort.log
    exit 1
fi

# Set ownership
chown ga:ga /home/ga/Videos/drone_flight_distorted.mp4

# Clean up temp file
rm -f /tmp/source_straight.mp4

echo "✅ Distorted video created: /home/ga/Videos/drone_flight_distorted.mp4"

# Launch VLC with the distorted video
echo "Launching VLC with distorted footage..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/drone_flight_distorted.mp4 > /tmp/vlc_distortion_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_distortion_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_distortion_task.log
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

# Let video play for a moment to ensure it's rendering
sleep 2

echo "=== Correct Lens Distortion Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a video with severe barrel distortion"
echo "  2. Notice the curved horizon line and warped grid"
echo "  3. Open Tools → Effects and Filters (Ctrl+E)"
echo "  4. Go to Video Effects → Geometry tab"
echo "  5. Enable Transform or other distortion correction filter"
echo "  6. Adjust parameters to straighten the horizon and grid"
echo "  7. Take a snapshot: Video → Take Snapshot (Shift+S)"
echo "  8. Save snapshot as: /home/ga/Pictures/vlc/corrected_view.png"
echo ""
echo "  Target output: /home/ga/Pictures/vlc/corrected_view.png"