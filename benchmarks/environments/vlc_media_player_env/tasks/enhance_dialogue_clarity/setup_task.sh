#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enhance Dialogue Clarity Task ==="

kill_vlc ga
sleep 1

# Reset VLC config to ensure no audio effects are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Backup original config
    cp "$VLC_RC" "$VLC_RC.backup.$(date +%s)"
    
    # Remove any existing audio effect settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^compressor-/d' "$VLC_RC"
    sed -i '/^norm-/d' "$VLC_RC"
    sed -i '/^normalizer/d' "$VLC_RC"
    sed -i '/^volume-save=/d' "$VLC_RC"
    sed -i '/^equalizer/d' "$VLC_RC"
    
    echo "Audio effects reset to default"
fi

# Ensure VLC config directory exists
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

# Launch VLC with RC interface enabled and a test video
# Use sample_video.mp4 which should have varying audio levels
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Videos/sample_video.mp4 > /tmp/vlc_dialogue_task.log 2>&1 &"

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

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully render and settle
sleep 2

echo "=== Enhance Dialogue Clarity Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing a video with varying audio levels"
echo "  2. Configure audio effects for dialogue clarity:"
echo ""
echo "  STEPS:"
echo "  a) Open: Tools → Effects and Filters (or press Ctrl+E)"
echo "  b) Go to 'Audio Effects' tab"
echo "  c) Enable 'Compressor' checkbox"
echo "  d) Configure Compressor:"
echo "     - Set Ratio to 6.0 or higher (aggressive compression)"
echo "     - Threshold: -15 to -20 dB"
echo "     - Adjust other parameters as needed"
echo "  e) Enable 'Volume normalizer' checkbox (or similar)"
echo "  f) (Optional) Enable Equalizer and boost mid-range frequencies"
echo "  g) Close dialog to apply and save settings"
echo ""
echo "  TARGET: Make quiet dialogue audible without excessive volume"