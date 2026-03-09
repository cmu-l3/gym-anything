#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Test Capture Devices Task ==="

kill_vlc ga
sleep 1

# Clean old VLC recordings from Videos directory to avoid false positives
echo "Cleaning old recordings..."
find /home/ga/Videos -name "vlc-record-*" -mmin +5 -delete 2>/dev/null || true
find /home/ga/Videos -name "*.mp4" -name "*.avi" -mmin +5 -type f -delete 2>/dev/null || true

# Ensure Videos directory exists
mkdir -p /home/ga/Videos
chown -R ga:ga /home/ga/Videos

# Record task start timestamp for verification
date +%s > /tmp/vlc_capture_task_start.txt
echo "Task started at: $(date)"

# Set up fake video device for testing (v4l2loopback)
echo "Setting up test video device..."

# Check if v4l2loopback module is available
if ! lsmod | grep -q v4l2loopback; then
    echo "Loading v4l2loopback kernel module..."
    modprobe v4l2loopback devices=1 video_nr=10 card_label="VLC Test Camera" exclusive_caps=1 || {
        echo "⚠️  Warning: Could not load v4l2loopback module"
        echo "   Continuing anyway - agent may use fake:// input"
    }
fi

# Feed test pattern to fake video device if available
if [ -e /dev/video10 ]; then
    echo "✅ Test video device available at /dev/video10"
    
    # Start background process to feed test pattern
    (
        su - ga -c "DISPLAY=:1 ffmpeg -f lavfi -i testsrc=size=640x480:rate=30 \
            -f lavfi -i sine=frequency=1000:sample_rate=48000 \
            -f v4l2 /dev/video10 -f alsa hw:0,0 \
            -t 300 > /tmp/ffmpeg_test_feed.log 2>&1" &
    ) || echo "⚠️  Warning: Could not start test pattern feed"
    
    sleep 2
else
    echo "⚠️  No v4l2loopback device, agent should use VLC's fake:// input"
fi

# Ensure PulseAudio is running for audio capture
su - ga -c "pulseaudio --check || pulseaudio --start" || echo "PulseAudio already running"
sleep 1

# Launch VLC with capture-friendly settings
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc \
    --avcodec-hw=none \
    --no-video-title-show \
    --verbose=2 \
    > /tmp/vlc_capture_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_capture_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Test Capture Devices Task Setup Complete ==="
echo ""
echo "📝 Instructions for Agent:"
echo "  1. Open Media → Open Capture Device (or press Ctrl+C)"
echo "  2. In the Capture Device dialog:"
echo "     - Video device: Select /dev/video10 (or use 'Fake' video input)"
echo "     - Audio device: Select 'pulse' or 'default' audio input"
echo "  3. Click 'Play' to start preview"
echo "  4. Click the Record button (red circle) to start recording"
echo "  5. Wait approximately 5 seconds"
echo "  6. Click Record button again to stop"
echo "  7. Recording will be saved to ~/Videos/"
echo ""
echo "🎥 Test devices available:"
if [ -e /dev/video10 ]; then
    echo "   - Video: /dev/video10 (test pattern)"
else
    echo "   - Video: Use 'fake://' or 'screen://' input"
fi
echo "   - Audio: PulseAudio (pulse://) or ALSA"
echo ""
echo "⏱️  Target: Record for ~5 seconds (acceptable range: 3-10 seconds)"