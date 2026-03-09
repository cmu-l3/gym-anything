#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Display Calibration Task ==="

kill_vlc ga
sleep 1

# Create test patterns directory
TEST_PATTERN_DIR="/home/ga/Videos/test_patterns"
mkdir -p "$TEST_PATTERN_DIR"
chown ga:ga "$TEST_PATTERN_DIR"

# Generate SMPTE color bars test pattern video
TEST_VIDEO="$TEST_PATTERN_DIR/smpte_colorbars_1080p.mp4"

if [ ! -f "$TEST_VIDEO" ]; then
    echo "Generating SMPTE color bar test pattern (60 seconds)..."
    
    # Create a 60-second SMPTE color bars test pattern
    su - ga -c "ffmpeg -f lavfi -i smptebars=size=1920x1080:rate=30 -t 60 -c:v libx264 -pix_fmt yuv420p -crf 18 '$TEST_VIDEO' -y" > /tmp/ffmpeg_testpattern.log 2>&1
    
    if [ ! -f "$TEST_VIDEO" ]; then
        echo "ERROR: Failed to generate test pattern video"
        cat /tmp/ffmpeg_testpattern.log
        exit 1
    fi
    
    echo "✅ Test pattern video created: $TEST_VIDEO"
else
    echo "Test pattern video already exists"
fi

# Modify VLC config to add video filters and non-neutral adjustments
# This simulates "messy real-world" state where VLC has been used with filters before
VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc

echo "Configuring VLC with non-neutral settings (simulating previous use)..."

# Remove any existing video filter/adjustment settings first
sed -i '/^video-filter=/d' "$VLC_CONFIG" 2>/dev/null || true
sed -i '/^vout-filter=/d' "$VLC_CONFIG" 2>/dev/null || true
sed -i '/^brightness=/d' "$VLC_CONFIG" 2>/dev/null || true
sed -i '/^contrast=/d' "$VLC_CONFIG" 2>/dev/null || true
sed -i '/^gamma=/d' "$VLC_CONFIG" 2>/dev/null || true
sed -i '/^saturation=/d' "$VLC_CONFIG" 2>/dev/null || true
sed -i '/^hue=/d' "$VLC_CONFIG" 2>/dev/null || true

# Add non-neutral video filters and adjustments
cat >> "$VLC_CONFIG" << 'EOF'

# Video filters enabled (agent must disable these)
video-filter=adjust

# Non-neutral video adjustments (agent must reset these)
brightness=1.15
contrast=1.08
gamma=1.1
saturation=1.05
hue=5

EOF

chown ga:ga "$VLC_CONFIG"

echo "✅ VLC config prepared with non-neutral settings"

# Launch VLC with the test pattern video loaded and paused
echo "Launching VLC with test pattern video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 '$TEST_VIDEO' > /tmp/vlc_calibration_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_calibration_task.log
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

# Pause the video initially so agent can configure settings first
sleep 1
echo "Pausing video for configuration..."
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Verify Display Calibration Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is now showing test pattern video (paused)"
echo "  2. Current state: Filters and adjustments are ACTIVE (non-neutral)"
echo "  3. Open Tools → Effects and Filters (Ctrl+E)"
echo "  4. Go to Video Effects tab"
echo "  5. DISABLE all video filters (uncheck any enabled filters)"
echo "  6. Reset all adjustments to neutral:"
echo "     - Brightness: 1.0"
echo "     - Contrast: 1.0"
echo "     - Gamma: 1.0"
echo "     - Saturation: 1.0"
echo "     - Hue: 0"
echo "  7. Close the Effects dialog"
echo "  8. Play the test pattern video to completion"
echo ""
echo "Test video location: $TEST_VIDEO"
echo "Video duration: 60 seconds"