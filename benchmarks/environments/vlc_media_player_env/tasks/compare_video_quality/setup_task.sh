#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Video Quality Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create comparison directories
mkdir -p /home/ga/Videos/comparison
mkdir -p /home/ga/Pictures/comparison
chown -R ga:ga /home/ga/Videos/comparison
chown -R ga:ga /home/ga/Pictures/comparison

# Clean any previous screenshots
rm -f /home/ga/Pictures/comparison/*.png

# Create two test videos with different characteristics
echo "Creating test videos for comparison..."

# Version A: Higher quality (actual 720p)
# Use existing sample video or create new one
if [ -f "/home/ga/Videos/sample_video.mp4" ]; then
    # Create version_a by re-encoding at good quality
    su - ga -c "ffmpeg -y -i /home/ga/Videos/sample_video.mp4 -t 180 -vf scale=1280:720 -c:v libx264 -crf 20 -preset medium -an /home/ga/Videos/comparison/version_a.mp4 > /tmp/ffmpeg_a.log 2>&1" || {
        echo "ERROR: Failed to create version_a"
        exit 1
    }
    
    # Version B: Lower quality (upscaled from 480p)
    su - ga -c "ffmpeg -y -i /home/ga/Videos/sample_video.mp4 -t 180 -vf scale=854:480,scale=1280:720 -c:v libx264 -crf 28 -preset fast -an /home/ga/Videos/comparison/version_b.mp4 > /tmp/ffmpeg_b.log 2>&1" || {
        echo "ERROR: Failed to create version_b"
        exit 1
    }
else
    # Fallback: Generate test videos from scratch
    echo "Generating test videos from scratch..."
    
    # Version A: Color bars with text, higher quality
    su - ga -c "ffmpeg -y -f lavfi -i testsrc=duration=180:size=1280x720:rate=30 -f lavfi -i anullsrc -c:v libx264 -crf 20 -preset medium -t 180 /home/ga/Videos/comparison/version_a.mp4 > /tmp/ffmpeg_a.log 2>&1" || {
        echo "ERROR: Failed to generate version_a"
        exit 1
    }
    
    # Version B: Same pattern but lower quality (simulated upscale)
    su - ga -c "ffmpeg -y -f lavfi -i testsrc=duration=180:size=1280x720:rate=30 -f lavfi -i anullsrc -c:v libx264 -crf 28 -preset fast -t 180 /home/ga/Videos/comparison/version_b.mp4 > /tmp/ffmpeg_b.log 2>&1" || {
        echo "ERROR: Failed to generate version_b"
        exit 1
    }
fi

# Verify both videos were created
if [ ! -f "/home/ga/Videos/comparison/version_a.mp4" ] || [ ! -f "/home/ga/Videos/comparison/version_b.mp4" ]; then
    echo "ERROR: Test videos not created"
    exit 1
fi

echo "✅ Test videos created:"
ls -lh /home/ga/Videos/comparison/

# Configure VLC snapshot directory
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^snapshot-path=/d' "$VLC_RC"
    echo "snapshot-path=/home/ga/Pictures/comparison" >> "$VLC_RC"
fi

# Launch first VLC instance with version_a
echo "Launching VLC instance 1 (version_a)..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --no-one-instance --avcodec-hw=none --no-video-title-show --video-title='Version A' /home/ga/Videos/comparison/version_a.mp4 > /tmp/vlc_compare_a.log 2>&1 &"

# Wait for first instance to start
sleep 3

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC instance 1 failed to start"
    exit 1
fi

# Launch second VLC instance with version_b
echo "Launching VLC instance 2 (version_b)..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --no-one-instance --avcodec-hw=none --no-video-title-show --video-title='Version B' /home/ga/Videos/comparison/version_b.mp4 > /tmp/vlc_compare_b.log 2>&1 &"

# Wait for both instances
sleep 3

# Check that we have 2 VLC processes
VLC_COUNT=$(pgrep -c vlc || echo 0)
if [ "$VLC_COUNT" -lt 2 ]; then
    echo "WARNING: Expected 2 VLC instances, found $VLC_COUNT"
fi

# Click on center of screen to select desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Try to position windows side-by-side
echo "Attempting to arrange windows side-by-side..."
WINDOW_IDS=$(wmctrl -l | grep -i vlc | awk '{print $1}')
WINDOW_COUNT=$(echo "$WINDOW_IDS" | wc -l)

if [ "$WINDOW_COUNT" -ge 2 ]; then
    WINDOW_1=$(echo "$WINDOW_IDS" | sed -n 1p)
    WINDOW_2=$(echo "$WINDOW_IDS" | sed -n 2p)
    
    # Position first window (left half)
    wmctrl -i -r "$WINDOW_1" -e 0,0,0,640,720 || true
    
    # Position second window (right half)
    wmctrl -i -r "$WINDOW_2" -e 0,640,0,640,720 || true
    
    echo "✅ Windows positioned"
else
    echo "⚠️ Could not position windows automatically (found $WINDOW_COUNT windows)"
fi

sleep 2

echo "=== Compare Video Quality Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Two VLC instances are running:"
echo "     - Instance 1: version_a.mp4"
echo "     - Instance 2: version_b.mp4"
echo "  2. Seek BOTH videos to timestamp 2:30 (150 seconds)"
echo "     Methods:"
echo "     - Press Ctrl+T, type '2:30', press Enter"
echo "     - Use seek bar to jump to 2:30"
echo "     - Use Shift+Right repeatedly to jump forward"
echo "  3. Pause both videos at 2:30"
echo "  4. Take screenshot of version_a:"
echo "     - Focus first window"
echo "     - Press Shift+S"
echo "     - Rename/move to: /home/ga/Pictures/comparison/version_a_frame.png"
echo "  5. Take screenshot of version_b:"
echo "     - Focus second window"
echo "     - Press Shift+S"
echo "     - Rename/move to: /home/ga/Pictures/comparison/version_b_frame.png"
echo ""
echo "  Note: VLC snapshots save to /home/ga/Pictures/comparison/ by default"
echo "  You may need to rename them from vlc-snap-*.png to the required names"