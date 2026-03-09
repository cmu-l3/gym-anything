#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Recording Settings Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/Documents

# Generate test video with specific specs matching expected camera settings
# This simulates a camera test recording at 4K 60fps H.264
echo "Generating test video with camera specs (4K 60fps H.264 ~80Mbps)..."

# Create 30-second test video with test pattern (simulates camera test footage)
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=30:size=3840x2160:rate=60 \
    -f lavfi -i sine=frequency=1000:duration=30 \
    -c:v libx264 -preset medium -profile:v high \
    -b:v 80M -maxrate 85M -bufsize 160M \
    -c:a aac -b:a 192k \
    -pix_fmt yuv420p \
    -r 60 \
    -movflags +faststart \
    -y /home/ga/Videos/camera_test.mp4 2>&1 | tee /tmp/ffmpeg_generation.log"

# Verify generation succeeded
if [ ! -f "/home/ga/Videos/camera_test.mp4" ]; then
    echo "ERROR: Failed to generate test video"
    cat /tmp/ffmpeg_generation.log
    exit 1
fi

FILE_SIZE=$(stat -c%s "/home/ga/Videos/camera_test.mp4" 2>/dev/null || stat -f%z "/home/ga/Videos/camera_test.mp4")
echo "✅ Generated test video: $((FILE_SIZE / 1024 / 1024)) MB"

# Log actual specs for debugging
echo "Actual video specifications:"
ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,codec_name,bit_rate \
    -of default=noprint_wrappers=1:nokey=1 \
    /home/ga/Videos/camera_test.mp4 2>&1 | tee /tmp/setup_actual_specs.log

# Set ownership
chown ga:ga /home/ga/Videos/camera_test.mp4

# Launch VLC with the test video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused /home/ga/Videos/camera_test.mp4 > /tmp/vlc_verify_settings_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_verify_settings_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_verify_settings_task.log
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 1

echo "=== Verify Recording Settings Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "============================================"
echo "You are a wedding videographer checking camera settings before tomorrow's shoot."
echo "The client requires: 4K (3840x2160), 60fps, H.264 codec, ≥80 Mbps bitrate"
echo ""
echo "Your task:"
echo "  1. The test video is already open in VLC"
echo "  2. Open codec information: Tools → Media Information (Ctrl+I)"
echo "  3. Go to 'Codec Details' tab"
echo "  4. Check the following specifications:"
echo "     - Resolution: Should be 3840x2160"
echo "     - Frame Rate: Should be 60 fps"
echo "     - Codec: Should be H.264 (or AVC1)"
echo "     - Bitrate: Should be ≥80 Mbps"
echo "  5. Create a report at: /home/ga/Documents/recording_verification.txt"
echo "  6. Report must include:"
echo "     - Each spec with actual vs expected value"
echo "     - Status (✓ or ✗) for each spec"
echo "     - Overall verdict: PASS or FAIL"
echo ""
echo "Example report format:"
echo "---"
echo "Camera Settings Verification Report"
echo "===================================="
echo "Resolution: 3840x2160 ✓ (Expected: 3840x2160)"
echo "Frame Rate: 60.00 fps ✓ (Expected: 60 fps)"
echo "Video Codec: H.264 ✓ (Expected: H.264)"
echo "Bitrate: 82.5 Mbps ✓ (Expected: ≥80 Mbps)"
echo ""
echo "Overall Verdict: PASS"
echo "---"
echo ""
echo "Test video location: /home/ga/Videos/camera_test.mp4"
echo "Report location: /home/ga/Documents/recording_verification.txt"
echo "============================================"