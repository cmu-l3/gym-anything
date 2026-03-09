#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify DVD Compatibility Task ==="

kill_vlc ga
sleep 1

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Create test video that is NOT DVD-compatible
# H.264 codec, 1920x1080 resolution, 30fps, AAC audio - all incompatible with DVD
TEST_VIDEO="/home/ga/Videos/family_reunion.mp4"

echo "Creating test video (H.264, 1920x1080, 30fps, AAC audio)..."

# Generate 30-second test video with known properties
ffmpeg -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=440:duration=30 \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 192k -ar 48000 -ac 2 \
       -y "$TEST_VIDEO" > /tmp/ffmpeg_video_gen.log 2>&1

if [ ! -f "$TEST_VIDEO" ]; then
    echo "ERROR: Failed to create test video"
    cat /tmp/ffmpeg_video_gen.log
    exit 1
fi

chown ga:ga "$TEST_VIDEO"

echo "✅ Test video created: $TEST_VIDEO"

# Verify test video properties with ffprobe
echo "Test video properties:"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate \
        -select_streams a:0 -show_entries stream=codec_name,channels,bit_rate \
        -of default=noprint_wrappers=1 "$TEST_VIDEO" 2>&1 | head -10

# Create empty report file with template
REPORT_FILE="/home/ga/Documents/dvd_compatibility_report.txt"

cat > "$REPORT_FILE" <<'EOF'
# DVD Compatibility Report Template
# 
# Replace this template with your analysis
# 
# Required sections:
# - VIDEO (Resolution, Frame Rate, Codec, Aspect Ratio)
# - AUDIO (Codec, Channels, Bitrate)
# - DURATION
# - OVERALL (COMPATIBLE / NEEDS CONVERSION)
# - RECOMMENDED ACTIONS
EOF

chown ga:ga "$REPORT_FILE"
chmod 666 "$REPORT_FILE"

echo "✅ Empty report template created: $REPORT_FILE"

# Launch VLC with the test video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$TEST_VIDEO' > /tmp/vlc_dvd_compat_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_dvd_compat_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for video to fully load
sleep 2

echo "=== Verify DVD Compatibility Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing the test video: family_reunion.mp4"
echo "  2. Open Media Information (Tools → Media Information or Ctrl+I)"
echo "  3. Go to 'Codec Information' tab"
echo "  4. Analyze video properties:"
echo "     - Resolution (should be 1920x1080 - NOT DVD compatible)"
echo "     - Frame Rate (should be 30 fps - NOT DVD compatible)"
echo "     - Video Codec (should be H264 - NOT DVD compatible)"
echo "     - Audio Codec (should be AAC - NOT DVD compatible)"
echo "  5. Write report to: /home/ga/Documents/dvd_compatibility_report.txt"
echo "  6. Include:"
echo "     - Actual specifications"
echo "     - PASS/FAIL for each parameter"
echo "     - OVERALL assessment"
echo "     - Specific conversion recommendations"
echo ""
echo "  DVD Standards:"
echo "    Video: 720x480 or 720x576, 29.97 or 25 fps, MPEG-2"
echo "    Audio: AC3, MP2, or LPCM"