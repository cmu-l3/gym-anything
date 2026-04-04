#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Smooth Playback Task ==="

kill_vlc ga
sleep 1

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Generate 4K test video (high bitrate to test performance)
echo "Generating 4K test video..."
if [ ! -f /home/ga/Videos/sample_4k_test.mp4 ]; then
    ffmpeg -f lavfi -i testsrc=duration=60:size=3840x2160:rate=25 \
      -c:v libx264 -preset fast -b:v 30M \
      /home/ga/Videos/sample_4k_test.mp4 2>/dev/null || \
    ffmpeg -f lavfi -i testsrc=duration=60:size=3840x2160:rate=25 \
      -c:v libx264 -preset ultrafast -b:v 30M \
      /home/ga/Videos/sample_4k_test.mp4
    
    chown ga:ga /home/ga/Videos/sample_4k_test.mp4
    echo "✅ 4K test video created"
fi

# Generate 1080p alternative
echo "Generating 1080p test video..."
if [ ! -f /home/ga/Videos/sample_1080p_test.mp4 ]; then
    ffmpeg -f lavfi -i testsrc=duration=60:size=1920x1080:rate=25 \
      -c:v libx264 -preset fast -b:v 5M \
      /home/ga/Videos/sample_1080p_test.mp4 2>/dev/null || \
    ffmpeg -f lavfi -i testsrc=duration=60:size=1920x1080:rate=25 \
      -c:v libx264 -preset ultrafast -b:v 5M \
      /home/ga/Videos/sample_1080p_test.mp4
    
    chown ga:ga /home/ga/Videos/sample_1080p_test.mp4
    echo "✅ 1080p test video created"
fi

# Launch VLC with RC interface for statistics querying
echo "Launching VLC with 4K test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 --start-paused /home/ga/Videos/sample_4k_test.mp4 > /tmp/vlc_playback_test.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Verify Smooth Playback Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Play the 4K test video for at least 30 seconds"
echo "  2. Access VLC's statistics:"
echo "     - Tools → Codec Information (Ctrl+J)"
echo "     - OR Tools → Media Information (Ctrl+I) → Statistics tab"
echo "  3. Record the following metrics:"
echo "     - Frames decoded"
echo "     - Frames displayed" 
echo "     - Frames lost/dropped"
echo "     - Duration tested"
echo "  4. Create report at: /home/ga/Documents/playback_stats.txt"
echo "  5. Report should include:"
echo "     - File tested (sample_4k_test.mp4)"
echo "     - Playback duration (≥30 seconds)"
echo "     - Frame statistics"
echo "     - Drop rate percentage"
echo "     - Verdict: SMOOTH or NOT SMOOTH (< 1% drops = smooth)"