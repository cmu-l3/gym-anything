#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Apply Effects Task ==="

kill_vlc ga
sleep 1

# Reset VLC config to ensure no effects are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing video adjustment settings
    sed -i '/^video-filter=/d' "$VLC_RC"
    sed -i '/^brightness=/d' "$VLC_RC"
    sed -i '/^contrast=/d' "$VLC_RC"
    echo "Effects reset"
fi

# Launch VLC with RC interface enabled and color test video
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Videos/color_test.mp4 > /tmp/vlc_effects_task.log 2>&1 &"

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

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Apply Effects Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open Tools -> Effects and Filters (Ctrl+E)"
echo "  2. Go to Video Effects tab"
echo "  3. Enable 'Image adjust' checkbox"
echo "  4. Adjust Brightness to ~1.5"
echo "  5. Adjust Contrast to ~1.5"
echo "  6. Close dialog to apply"
