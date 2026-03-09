#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Auto Stop Sleep Timer Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 2

# Ensure Pictures directory exists for any potential snapshots
mkdir -p /home/ga/Pictures/vlc
chown -R ga:ga /home/ga/Pictures

# Clear any old timing marker files
rm -f /tmp/vlc_start_time.txt
rm -f /tmp/vlc_end_time.txt
rm -f /tmp/vlc_sleep_timer.log
rm -f /tmp/vlc_launch_cmd.txt

# Verify video file exists (use 10-minute loopable video)
VIDEO_PATH="/home/ga/Videos/sample_video.mp4"
if [ ! -f "$VIDEO_PATH" ]; then
    echo "ERROR: Sample video not found: $VIDEO_PATH"
    exit 1
fi

echo "=== Auto Stop Sleep Timer Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 OBJECTIVE: Configure VLC to automatically quit after 45 seconds"
echo ""
echo "📹 Video file: $VIDEO_PATH"
echo "⏱️  Target runtime: 45 seconds (±10s tolerance)"
echo ""
echo "✅ Recommended approach (Method 1):"
echo "   Launch VLC with --run-time flag:"
echo "   vlc --run-time=45 --play-and-exit $VIDEO_PATH"
echo ""
echo "🔧 Alternative Method 2:"
echo "   Use timeout command:"
echo "   timeout 45 vlc $VIDEO_PATH"
echo ""
echo "🔧 Alternative Method 3:"
echo "   Launch VLC and schedule kill:"
echo "   vlc $VIDEO_PATH &"
echo "   sleep 45 && pkill vlc"
echo ""
echo "⚠️  IMPORTANT: Record start time when launching VLC!"
echo "   You can use: date +%s > /tmp/vlc_start_time.txt"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"