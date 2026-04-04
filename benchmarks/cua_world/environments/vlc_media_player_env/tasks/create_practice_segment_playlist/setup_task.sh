#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Practice Segment Playlist Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Videos/dance_tutorials
mkdir -p /home/ga/Videos/playlists
chown -R ga:ga /home/ga/Videos/

echo "Generating tutorial videos with timestamps..."

# Video 1: 10:30 duration (630 seconds) - body isolation section at 2:15-2:45
echo "Creating tutorial_01_basics.mp4 (10:30)..."
ffmpeg -f lavfi -i color=c=blue:s=1280x720:d=630 \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='TUTORIAL 1 - BASICS':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=100:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Body Isolation 2\\\:15-2\\\:45':fontsize=48:fontcolor=yellow:x=(w-text_w)/2:y=200:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Time\\\: %{pts\\:hms}':fontsize=56:fontcolor=yellow:x=(w-text_w)/2:y=(h-150):box=1:boxcolor=black@0.7:boxborderw=5" \
  -f lavfi -i "sine=frequency=300:duration=630" \
  -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 64k -shortest \
  /home/ga/Videos/dance_tutorials/tutorial_01_basics.mp4 -y 2>/dev/null

# Video 2: 12:15 duration (735 seconds) - footwork section at 4:30-5:00
echo "Creating tutorial_02_intermediate.mp4 (12:15)..."
ffmpeg -f lavfi -i color=c=green:s=1280x720:d=735 \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='TUTORIAL 2 - INTERMEDIATE':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=100:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Footwork Combo 4\\\:30-5\\\:00':fontsize=48:fontcolor=yellow:x=(w-text_w)/2:y=200:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Time\\\: %{pts\\:hms}':fontsize=56:fontcolor=yellow:x=(w-text_w)/2:y=(h-150):box=1:boxcolor=black@0.7:boxborderw=5" \
  -f lavfi -i "sine=frequency=400:duration=735" \
  -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 64k -shortest \
  /home/ga/Videos/dance_tutorials/tutorial_02_intermediate.mp4 -y 2>/dev/null

# Video 3: 8:45 duration (525 seconds) - arm movements at 1:00-1:40
echo "Creating tutorial_03_arms.mp4 (8:45)..."
ffmpeg -f lavfi -i color=c=red:s=1280x720:d=525 \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='TUTORIAL 3 - ARMS':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=100:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Arm Movements 1\\\:00-1\\\:40':fontsize=48:fontcolor=yellow:x=(w-text_w)/2:y=200:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Time\\\: %{pts\\:hms}':fontsize=56:fontcolor=yellow:x=(w-text_w)/2:y=(h-150):box=1:boxcolor=black@0.7:boxborderw=5" \
  -f lavfi -i "sine=frequency=500:duration=525" \
  -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 64k -shortest \
  /home/ga/Videos/dance_tutorials/tutorial_03_arms.mp4 -y 2>/dev/null

# Video 4: 11:00 duration (660 seconds) - cooldown at 8:00-9:30
echo "Creating tutorial_04_cooldown.mp4 (11:00)..."
ffmpeg -f lavfi -i color=c=purple:s=1280x720:d=660 \
  -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='TUTORIAL 4 - COOLDOWN':fontsize=64:fontcolor=white:x=(w-text_w)/2:y=100:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Stretching 8\\\:00-9\\\:30':fontsize=48:fontcolor=yellow:x=(w-text_w)/2:y=200:box=1:boxcolor=black@0.5:boxborderw=5, \
       drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Time\\\: %{pts\\:hms}':fontsize=56:fontcolor=yellow:x=(w-text_w)/2:y=(h-150):box=1:boxcolor=black@0.7:boxborderw=5" \
  -f lavfi -i "sine=frequency=350:duration=660" \
  -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 64k -shortest \
  /home/ga/Videos/dance_tutorials/tutorial_04_cooldown.mp4 -y 2>/dev/null

# Set ownership
chown -R ga:ga /home/ga/Videos/

echo "✅ Tutorial videos created successfully"
ls -lh /home/ga/Videos/dance_tutorials/

# Launch VLC (empty, for agent to work with)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_playlist_segment_task.log 2>&1 &"

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

echo "=== Create Practice Segment Playlist Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  Create a playlist file at: /home/ga/Videos/playlists/practice_sequence.xspf (or .m3u8)"
echo ""
echo "  Required segments (in order):"
echo "    1. tutorial_01_basics.mp4     → 2:15-2:45  (135-165 seconds)"
echo "    2. tutorial_02_intermediate.mp4 → 4:30-5:00  (270-300 seconds)"
echo "    3. tutorial_03_arms.mp4        → 1:00-1:40  (60-100 seconds)"
echo "    4. tutorial_04_cooldown.mp4    → 8:00-9:30  (480-570 seconds)"
echo ""
echo "  The playlist must specify start and stop times for each segment."
echo "  Total duration should be approximately 205 seconds (3:25)."
echo ""
echo "  Tip: Use M3U8 format with #EXTVLCOPT:start-time=X and #EXTVLCOPT:stop-time=Y"