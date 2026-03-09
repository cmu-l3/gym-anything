#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Restoration Quality Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create task directory
TASK_DIR="/home/ga/Videos/restoration_comparison"
mkdir -p "$TASK_DIR"

# Ensure snapshot directory exists
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
mkdir -p "$SNAPSHOT_DIR"

# Clean any old snapshots from this task
rm -f "$SNAPSHOT_DIR"/restoration_*.png
rm -f "$SNAPSHOT_DIR"/*original*.png
rm -f "$SNAPSHOT_DIR"/*restored*.png

cd "$TASK_DIR"

echo "Creating test videos simulating original and restored footage..."

# Create original video: lower quality with noise and reduced saturation
# Simulate aged film look
ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=24 \
    -vf "noise=alls=20:allf=t,hue=s=0.7,eq=brightness=-0.1:contrast=0.9" \
    -c:v libx264 -crf 28 -preset fast \
    -y original_scan.mp4 2>/dev/null

if [ ! -f "original_scan.mp4" ] || [ ! -s "original_scan.mp4" ]; then
    echo "ERROR: Failed to create original_scan.mp4"
    exit 1
fi

echo "✅ Created original_scan.mp4"

# Create restored video: higher quality, no noise, better colors
# Simulate professional restoration
ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=24 \
    -vf "hue=s=1.0,eq=brightness=0:contrast=1.1" \
    -c:v libx264 -crf 18 -preset fast \
    -y restored_version.mp4 2>/dev/null

if [ ! -f "restored_version.mp4" ] || [ ! -s "restored_version.mp4" ]; then
    echo "ERROR: Failed to create restored_version.mp4"
    exit 1
fi

echo "✅ Created restored_version.mp4"

# Set ownership
chown -R ga:ga "$TASK_DIR"
chown -R ga:ga "$SNAPSHOT_DIR"

# Launch VLC with a simple starting point (user will need to open both videos)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_compare_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Compare Restoration Quality Task Setup Complete ==="
echo ""
echo "📁 Video files created in: $TASK_DIR"
echo "   - original_scan.mp4 (unprocessed, noisy)"
echo "   - restored_version.mp4 (clean, enhanced)"
echo ""
echo "📝 Instructions:"
echo "  1. Open BOTH video files in VLC (you may need multiple windows/instances)"
echo "  2. Navigate to timestamp 00:15 in BOTH videos"
echo "  3. Pause both videos at 00:15"
echo "  4. Take snapshot from original video (Shift+S)"
echo "  5. Take snapshot from restored video (Shift+S)"
echo "  6. Rename snapshots to include 'original' and 'restored' in filenames"
echo ""
echo "💡 Tips:"
echo "  - You can open a new VLC instance to have both videos side-by-side"
echo "  - Snapshots are saved to: $SNAPSHOT_DIR"
echo "  - Use file manager or mv command to rename snapshots"
echo "  - The 15-second mark is where important details (text/faces) appear"