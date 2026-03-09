#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compress for Platform Limit Task ==="

kill_vlc ga
sleep 1

# Define paths
SOURCE_VIDEO="/home/ga/Videos/birthday_clip_source.mp4"
OUTPUT_DIR="/home/ga/Videos/compressed"
OUTPUT_VIDEO="$OUTPUT_DIR/birthday_email.mp4"

# Ensure output directory exists and is owned by ga
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Clean any previous outputs
rm -f "$OUTPUT_VIDEO"
rm -f "$SOURCE_VIDEO"

echo "Creating source video (45 seconds, ~35MB)..."

# Generate realistic source video: 45 seconds, 1080p, high bitrate to ensure >10MB size
# Use testsrc2 for more realistic content than plain testsrc
su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=45:size=1920x1080:rate=30 \
  -f lavfi -i sine=frequency=440:duration=45 \
  -c:v libx264 -preset medium -crf 18 -b:v 6000k \
  -c:a aac -b:a 192k \
  -pix_fmt yuv420p \
  -y '$SOURCE_VIDEO' 2>/dev/null"

# Verify source was created
if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: Failed to create source video"
    exit 1
fi

# Check source file size
SOURCE_SIZE=$(stat -c%s "$SOURCE_VIDEO" 2>/dev/null || stat -f%z "$SOURCE_VIDEO" 2>/dev/null)
SOURCE_SIZE_MB=$(echo "scale=2; $SOURCE_SIZE/1024/1024" | bc)
echo "Source video created: ${SOURCE_SIZE_MB}MB"

# Ensure source is actually over 10MB, otherwise regenerate with higher bitrate
TARGET_SIZE=10485760  # 10MB in bytes
if [ "$SOURCE_SIZE" -lt "$TARGET_SIZE" ]; then
    echo "WARNING: Source video is under 10MB (${SOURCE_SIZE_MB}MB), regenerating with higher bitrate..."
    su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=45:size=1920x1080:rate=30 \
      -f lavfi -i sine=frequency=440:duration=45 \
      -c:v libx264 -preset slow -crf 15 -b:v 8000k \
      -c:a aac -b:a 256k \
      -pix_fmt yuv420p \
      -y '$SOURCE_VIDEO' 2>/dev/null"
    
    SOURCE_SIZE=$(stat -c%s "$SOURCE_VIDEO" 2>/dev/null || stat -f%z "$SOURCE_VIDEO" 2>/dev/null)
    SOURCE_SIZE_MB=$(echo "scale=2; $SOURCE_SIZE/1024/1024" | bc)
    echo "Regenerated source video: ${SOURCE_SIZE_MB}MB"
fi

# Verify source duration
SOURCE_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null)
echo "Source video duration: ${SOURCE_DURATION}s"

# Launch VLC (empty, agent will use Convert/Save dialog)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_compress_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_compress_task.log
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

echo "=== Compress for Platform Limit Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SCENARIO: You need to email a 45-second video clip to family,"
echo "          but your email has a 10MB attachment limit."
echo "          The original video is ${SOURCE_SIZE_MB}MB."
echo ""
echo "GOAL: Compress the video to under 10MB while keeping it watchable."
echo ""
echo "STEPS:"
echo "  1. Open Media → Convert/Save (or press Ctrl+R)"
echo "  2. Click 'Add' and select: $SOURCE_VIDEO"
echo "  3. Click 'Convert/Save' button at bottom"
echo "  4. In Convert dialog:"
echo "     - Profile: Select 'Video - H.264 + MP3 (MP4)' or similar"
echo "     - Click wrench icon to edit profile:"
echo "       • Video bitrate: 1000-1500 kbps"
echo "       • Resolution: 720p or 480p (reduce from 1080p)"
echo "       • Audio bitrate: 96-128 kbps"
echo "     - Destination file: $OUTPUT_VIDEO"
echo "  5. Click 'Start' to begin conversion"
echo "  6. Wait for conversion to complete"
echo ""
echo "TIP: Lower bitrate/resolution = smaller file, but worse quality."
echo "     Aim for ~1200 kbps video + 128 kbps audio for good balance."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"