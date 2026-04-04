#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Magnify Distant Subject Task ==="

kill_vlc ga
sleep 1

# Ensure output directory exists
mkdir -p /home/ga/Videos/magnified
chown ga:ga /home/ga/Videos/magnified

# Generate wildlife video with small bird in upper-right quadrant
echo "Generating wildlife footage with distant bird..."
cd /home/ga/Videos

# Create base nature background (green/forest-like with texture)
ffmpeg -f lavfi -i "color=c=0x4a7c4e:s=1920x1080:d=30,format=rgb24" \
    -vf "geq=r='200*random(1)':g='150+100*random(1)':b='80*random(1)',noise=alls=10:allf=t" \
    -r 30 -pix_fmt yuv420p -y /tmp/background_temp.mp4 2>/dev/null || {
        echo "ERROR: Failed to create background video"
        exit 1
    }

# Create small bird-like object (50x50 pixels, brownish-red with slight variation)
ffmpeg -f lavfi -i "color=c=0x8b4513:s=50x50:d=30,format=rgb24" \
    -vf "geq=r='200+random(1)*55':g='100+random(1)*50':b='50+random(1)*30'" \
    -r 30 -pix_fmt yuv420p -y /tmp/bird_temp.mp4 2>/dev/null || {
        echo "ERROR: Failed to create bird overlay"
        exit 1
    }

# Overlay small bird in upper-right quadrant with gentle oscillating movement
# Position: x around 1400-1500, y around 300-400 (upper-right region)
ffmpeg -i /tmp/background_temp.mp4 -i /tmp/bird_temp.mp4 \
    -filter_complex "[1:v]scale=50:50[bird];[0:v][bird]overlay=x='1400+60*sin(t*0.5)':y='300+40*cos(t*0.8)':shortest=1" \
    -c:v libx264 -preset fast -crf 23 -r 30 -t 30 -pix_fmt yuv420p -y wildlife_distant_bird.mp4 2>/dev/null || {
        echo "ERROR: Failed to create wildlife video"
        exit 1
    }

# Cleanup temp files
rm -f /tmp/background_temp.mp4 /tmp/bird_temp.mp4

# Verify video was created
if [ ! -f wildlife_distant_bird.mp4 ]; then
    echo "ERROR: Wildlife video not created"
    exit 1
fi

# Check video duration
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 wildlife_distant_bird.mp4 2>/dev/null || echo "0")
if (( $(echo "$DURATION < 25" | bc -l) )); then
    echo "ERROR: Wildlife video too short (${DURATION}s)"
    exit 1
fi

# Set ownership
chown ga:ga wildlife_distant_bird.mp4

echo "✅ Wildlife video created: wildlife_distant_bird.mp4"
ls -lh wildlife_distant_bird.mp4

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_magnify_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

echo "=== Magnify Distant Subject Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GOAL: Magnify the distant bird in the upper-right region"
echo ""
echo "  SOURCE VIDEO: /home/ga/Videos/wildlife_distant_bird.mp4"
echo "  OUTPUT VIDEO: /home/ga/Videos/magnified/bird_closeup.mp4"
echo ""
echo "  The bird is located in the upper-right quadrant:"
echo "    • Approximate horizontal: x = 1200-1700 pixels"
echo "    • Approximate vertical: y = 200-600 pixels"
echo ""
echo "  APPROACH:"
echo "  1. Open the wildlife video in VLC"
echo "  2. Apply crop filter to the upper-right region:"
echo "     → Media → Convert/Save (Ctrl+R)"
echo "     → Add: /home/ga/Videos/wildlife_distant_bird.mp4"
echo "     → Click 'Convert/Save'"
echo "     → Edit profile → Video codec → Filters tab"
echo "     → Add 'Video cropping filter' or use Tools → Effects"
echo "  3. Set crop coordinates to focus on upper-right"
echo "  4. Save to: /home/ga/Videos/magnified/bird_closeup.mp4"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"