#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Examine Video Metadata Task ==="

kill_vlc ga
sleep 1

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Generate a test video with known metadata
TEST_VIDEO="/home/ga/Videos/documentary_footage.mp4"
GROUND_TRUTH="/tmp/metadata_ground_truth.json"

echo "Generating test video with known metadata..."

# Create a 15-second test video with specific properties
# Using testsrc pattern for visual content
CREATION_TIME="2024-03-15T14:30:00"
ARTIST="Documentary Crew A"
COPYRIGHT="2024 Archive Project"

su - ga -c "ffmpeg -y -f lavfi -i testsrc=duration=15:size=1920x1080:rate=30 \
  -f lavfi -i sine=frequency=440:duration=15 \
  -c:v libx264 -preset fast -b:v 5000k -g 60 \
  -c:a aac -b:a 128k \
  -metadata creation_time='${CREATION_TIME}' \
  -metadata artist='${ARTIST}' \
  -metadata copyright='${COPYRIGHT}' \
  -metadata comment='Test video for metadata extraction' \
  '${TEST_VIDEO}' > /tmp/ffmpeg_metadata_gen.log 2>&1" || {
    echo "ERROR: Failed to generate test video"
    cat /tmp/ffmpeg_metadata_gen.log
    exit 1
}

echo "✅ Test video generated: $TEST_VIDEO"

# Extract ground truth metadata using ffprobe
echo "Extracting ground truth metadata..."

VIDEO_INFO=$(ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate \
  -show_entries format=duration,bit_rate \
  -of json \
  "$TEST_VIDEO" 2>/dev/null)

# Parse ground truth values
CODEC=$(echo "$VIDEO_INFO" | jq -r '.streams[0].codec_name // "h264"')
WIDTH=$(echo "$VIDEO_INFO" | jq -r '.streams[0].width // 1920')
HEIGHT=$(echo "$VIDEO_INFO" | jq -r '.streams[0].height // 1080')
FPS_FRACTION=$(echo "$VIDEO_INFO" | jq -r '.streams[0].r_frame_rate // "30/1"')
BITRATE=$(echo "$VIDEO_INFO" | jq -r '.streams[0].bit_rate // .format.bit_rate // "5000000"')

# Convert frame rate fraction to decimal
if [[ "$FPS_FRACTION" =~ ^([0-9]+)/([0-9]+)$ ]]; then
    FPS=$(echo "scale=2; ${BASH_REMATCH[1]} / ${BASH_REMATCH[2]}" | bc)
else
    FPS="30.00"
fi

# Convert bitrate to kb/s
BITRATE_KBPS=$(echo "scale=0; $BITRATE / 1000" | bc)

# Store ground truth as JSON
cat > "$GROUND_TRUTH" <<EOF
{
    "codec": "$CODEC",
    "width": $WIDTH,
    "height": $HEIGHT,
    "fps": $FPS,
    "bitrate_kbps": $BITRATE_KBPS,
    "creation_time": "$CREATION_TIME",
    "artist": "$ARTIST",
    "copyright": "$COPYRIGHT",
    "resolution": "${WIDTH}x${HEIGHT}"
}
EOF

echo "✅ Ground truth saved to $GROUND_TRUTH"
cat "$GROUND_TRUTH"

# Ensure ground truth is readable by ga user (for potential alternative approaches)
chmod 644 "$GROUND_TRUTH"

# Launch VLC with the test video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show '${TEST_VIDEO}' > /tmp/vlc_metadata_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_metadata_task.log
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

# Pause video to make examination easier
echo "Pausing video for examination..."
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Examine Video Metadata Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing documentary_footage.mp4"
echo "  2. Open Media Information dialog:"
echo "     - Tools → Media Information"
echo "     - Or press Ctrl+I"
echo "  3. Navigate through tabs:"
echo "     - General: Basic file info"
echo "     - Codec Information: Technical specs (codec, resolution, fps, bitrate)"
echo "     - Metadata: Embedded metadata (creation date, artist, copyright)"
echo "  4. Extract the following information:"
echo "     - Video Codec (e.g., H264)"
echo "     - Resolution (e.g., 1920x1080)"
echo "     - Frame Rate (e.g., 30 fps)"
echo "     - Bitrate (e.g., 5000 kb/s)"
echo "     - Creation Date (if visible)"
echo "  5. Document findings in: /home/ga/Documents/metadata_report.txt"
echo "  6. Format: Clear labels with values (e.g., 'Video Codec: H264')"
echo ""
echo "Expected values:"
echo "  Codec: $CODEC"
echo "  Resolution: ${WIDTH}x${HEIGHT}"
echo "  Frame Rate: ${FPS} fps"
echo "  Bitrate: ~${BITRATE_KBPS} kb/s"