#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Timecode Overlay Task ==="

kill_vlc ga
sleep 1

# Reset VLC config to ensure no time overlay is active initially
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing time overlay settings
    sed -i '/^time-overlay=/d' "$VLC_RC"
    sed -i '/^time-position=/d' "$VLC_RC"
    sed -i '/^time-opacity=/d' "$VLC_RC"
    sed -i '/^time-color=/d' "$VLC_RC"
    sed -i '/^marq-marquee=/d' "$VLC_RC"
    sed -i '/^sub-source=/d' "$VLC_RC"
    echo "Time overlay settings reset"
fi

# Create output directory for any screenshots or exports
mkdir -p /home/ga/Videos/timecode_output
chown ga:ga /home/ga/Videos/timecode_output

# Create a test video with varied brightness (alternating scenes)
# This tests timecode visibility across different backgrounds
TEST_VIDEO="/home/ga/Videos/timecode_test_video.mp4"

if [ ! -f "$TEST_VIDEO" ]; then
    echo "Creating test video with varied brightness..."
    
    # Generate 3-minute video with alternating bright/dark/gray scenes
    # Each scene is 30 seconds for a total of 180 seconds
    ffmpeg -f lavfi -i "color=c=white:s=1280x720:r=30:d=30" \
           -f lavfi -i "color=c=black:s=1280x720:r=30:d=30" \
           -f lavfi -i "color=c=gray:s=1280x720:r=30:d=30" \
           -f lavfi -i "color=c=white:s=1280x720:r=30:d=30" \
           -f lavfi -i "color=c=black:s=1280x720:r=30:d=30" \
           -f lavfi -i "color=c=gray:s=1280x720:r=30:d=30" \
           -filter_complex "[0:v][1:v][2:v][3:v][4:v][5:v]concat=n=6:v=1[v]; \
                            [v]drawtext=text='Film Project - Review Draft': \
                            x=(w-text_w)/2:y=(h-text_h)/2:fontsize=48: \
                            fontcolor=red:shadowcolor=black:shadowx=3:shadowy=3[outv]" \
           -map "[outv]" -c:v libx264 -preset ultrafast -crf 28 -t 180 \
           "$TEST_VIDEO" -y 2>/tmp/vlc_timecode_video_gen.log
    
    chown ga:ga "$TEST_VIDEO"
    echo "✅ Test video created: $TEST_VIDEO"
else
    echo "Test video already exists: $TEST_VIDEO"
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TEST_VIDEO' > /tmp/vlc_timecode_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_timecode_task.log
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

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Let video play for a moment to initialize
sleep 2

echo "=== Add Timecode Overlay Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a test video with alternating brightness"
echo "  2. Open: Tools → Effects and Filters (Ctrl+E)"
echo "  3. Go to: Video Effects tab → Overlay sub-tab"
echo "  4. Enable the 'Time' checkbox to show timecode overlay"
echo "  5. The timecode should appear on screen (typically top-left or top-right)"
echo "  6. Optional: Take a screenshot (Shift+S) to verify visibility"
echo "  7. Close the Effects dialog - settings will be saved"
echo ""
echo "Expected: Timecode overlay like '00:00:15' visible during playback"