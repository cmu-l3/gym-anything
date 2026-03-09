#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Movement Analysis Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Ensure Pictures directory exists for any screenshots
mkdir -p /home/ga/Pictures/vlc
chown ga:ga /home/ga/Pictures/vlc

# Create a training video if not exists (movement-focused content)
TRAINING_VIDEO="/home/ga/Videos/training_movement.mp4"

if [ ! -f "$TRAINING_VIDEO" ]; then
    echo "Creating training movement video..."
    # Create a 60-second video with clear temporal markers for movement analysis
    # Using testsrc with moving elements to simulate movement
    ffmpeg -f lavfi -i "testsrc=duration=60:size=1280x720:rate=30,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='Movement Training Video':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=50:box=1:boxcolor=black@0.5:boxborderw=5,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='%{pts\:hms}':fontcolor=yellow:fontsize=36:x=(w-text_w)/2:y=h-100:box=1:boxcolor=black@0.7:boxborderw=5" \
           -f lavfi -i "sine=frequency=440:duration=60" \
           -c:v libx264 -preset ultrafast -c:a aac \
           "$TRAINING_VIDEO" 2>/dev/null || {
        echo "Warning: Could not create training video, using sample video"
        TRAINING_VIDEO="/home/ga/Videos/sample_video.mp4"
    }
    
    chown ga:ga "$TRAINING_VIDEO" 2>/dev/null || true
fi

# Reset VLC config to ensure clean state for OSD settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing OSD/time display settings to ensure clean state
    sed -i '/^qt-time-display=/d' "$VLC_RC"
    sed -i '/^qt-show-time=/d' "$VLC_RC"
    sed -i '/^osd=/d' "$VLC_RC"
    echo "OSD settings reset"
fi

# Launch VLC with RC interface enabled for runtime state queries
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TRAINING_VIDEO' > /tmp/vlc_movement_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_movement_task.log
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
    echo "RC interface not ready, waiting..."
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

# Let video play for a moment to ensure it's fully loaded
sleep 2

# Pause video so agent can work with it
echo "Pausing video for configuration..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

echo "=== Configure Movement Analysis Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "======================================"
echo "Configure VLC for detailed movement analysis used by martial artists and dancers:"
echo ""
echo "1. ADJUST PLAYBACK SPEED (50-75%):"
echo "   • Use Playback → Speed → Slower (or press ']' key repeatedly)"
echo "   • Target: 50-75% speed for detailed analysis"
echo "   • Verify speed indicator appears on screen"
echo ""
echo "2. CONFIGURE A-B REPEAT LOOP:"
echo "   • Play video and identify a movement segment"
echo "   • Press 'A-B Loop' button or Shift+L at START of movement"
echo "   • Let video play 3-5 seconds"
echo "   • Press 'A-B Loop' button or Shift+L again at END"
echo "   • Video should now loop that segment automatically"
echo ""
echo "3. ENABLE ON-SCREEN TIME DISPLAY:"
echo "   • Press 'T' key to toggle time display"
echo "   • OR: Tools → Preferences → Interface → Show media time"
echo "   • Verify timestamp appears on video"
echo ""
echo "4. VERIFY COMPLETE SETUP:"
echo "   • Video plays at reduced speed ✓"
echo "   • Loop repeats automatically ✓"
echo "   • Time display visible ✓"
echo ""
echo "Training video: $TRAINING_VIDEO"
echo "======================================"