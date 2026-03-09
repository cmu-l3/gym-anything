#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adjust Volume Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Reset VLC volume to default (100% = 256)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i 's/audio-volume=.*/audio-volume=256/' "$VLC_RC"
    echo "Volume reset to 100%"
fi

# Check if vlc is already running and kill it
if pgrep -f "vlc" > /dev/null; then
    echo "VLC is already running, killing it..."
    pkill -f "vlc"
    sleep 1
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 vlc --avcodec-hw=none --extraintf rc --rc-host localhost:9999 /home/ga/Videos/sample_video.mp4 > /tmp/vlc_volume_task.log 2>&1 &"



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
    echo "RC interface not ready, waiting..."
    sleep 1
done

# Wait for VLC to fully render
sleep 3

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Click on screen to trigger VLC window rendering
echo "Triggering window rendering..."
su - ga -c "DISPLAY=:1 xdotool mousemove 400 300 click 1" || true
sleep 1

echo "=== Adjust Volume Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing a video at 100% volume"
echo "  2. Adjust volume to 75% using:"
echo "     - Volume slider in GUI"
echo "     - Keyboard shortcuts (Ctrl+Down to decrease)"
echo "  3. Target: 75% volume (192 in VLC config)"
