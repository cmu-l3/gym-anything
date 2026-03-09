#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Bookmark Study Scenes Task ==="

kill_vlc ga
sleep 1

# Prepare the educational video (25 minutes, 1500 seconds)
LECTURE_VIDEO="/home/ga/Videos/lecture_video.mp4"

if [ ! -f "$LECTURE_VIDEO" ]; then
    echo "Generating 25-minute educational video..."
    
    # Create a 25-minute test pattern video with visual markers every 5 minutes
    # This simulates an educational lecture with distinct sections
    su - ga -c "ffmpeg -f lavfi -i testsrc=duration=1500:size=1280x720:rate=30 \
        -f lavfi -i sine=frequency=440:duration=1500 \
        -vf \"drawtext=fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2:text='Educational Lecture %{pts\\\:hms}':fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf\" \
        -c:v libx264 -preset ultrafast -c:a aac -t 1500 \
        '$LECTURE_VIDEO' -y > /tmp/ffmpeg_lecture.log 2>&1" || {
        echo "ERROR: Failed to generate video"
        cat /tmp/ffmpeg_lecture.log
        exit 1
    }
    
    chown ga:ga "$LECTURE_VIDEO"
    echo "✅ Lecture video generated: $(ls -lh $LECTURE_VIDEO)"
fi

# Clear any existing bookmarks and media library to ensure clean slate
echo "Clearing existing bookmarks..."
rm -f /home/ga/.local/share/vlc/ml.xspf
rm -f /home/ga/.local/share/vlc/ml.db
rm -f /home/ga/.config/vlc/bookmarks.xspf
mkdir -p /home/ga/.local/share/vlc
chown -R ga:ga /home/ga/.local/share/vlc

# Launch VLC with RC interface enabled
echo "Launching VLC with lecture video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused --extraintf rc --rc-host localhost:9999 '$LECTURE_VIDEO' > /tmp/vlc_bookmark_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_bookmark_task.log
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

# Additional wait for VLC to fully initialize
sleep 2

echo "=== Bookmark Study Scenes Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a 25-minute educational lecture video"
echo "  2. Create bookmarks at key timestamps:"
echo "     - Introduction (~1:15 / 75s)"
echo "     - First Concept (~6:15 / 375s)"
echo "     - Second Concept (~12:30 / 750s)"
echo "     - Third Concept (~18:45 / 1125s)"
echo "     - Summary (~22:30 / 1350s)"
echo "  3. Navigate to: Playback → Custom Bookmarks → Manage"
echo "  4. For each timestamp:"
echo "     - Seek to the timestamp (use timeline or keyboard)"
echo "     - Click 'Create' in bookmark dialog"
echo "     - Give it a descriptive name (e.g., 'Introduction', 'Neural Networks')"
echo "  5. Bookmarks will be saved automatically"
echo ""
echo "Video duration: 25:00 (1500 seconds)"