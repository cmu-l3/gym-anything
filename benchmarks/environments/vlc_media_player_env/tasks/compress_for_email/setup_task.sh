#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compress for Email Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Videos/compressed
chown -R ga:ga /home/ga/Videos/compressed

# Create source video: 2min 15sec, 1080p, ~75-80MB
SOURCE_VIDEO="/home/ga/Videos/email_source.mp4"
INFO_FILE="/tmp/email_source_info.json"

echo "Generating source video (this may take 30 seconds)..."

# Generate high-quality 1080p video with realistic size
# Using testsrc2 for more visually interesting content than testsrc
# Duration: 135 seconds (2:15)
# Resolution: 1920x1080
# Video bitrate: 4500 kbps (to achieve ~75MB total)
# Audio bitrate: 192 kbps
su - ga -c "ffmpeg -f lavfi -i testsrc2=duration=135:size=1920x1080:rate=30 \
       -f lavfi -i sine=frequency=440:duration=135 \
       -c:v libx264 -preset medium -b:v 4500k \
       -c:a aac -b:a 192k \
       -pix_fmt yuv420p \
       -y '$SOURCE_VIDEO' 2>/dev/null" || {
    echo "ERROR: Failed to generate source video"
    exit 1
}

# Verify source video was created
if [ ! -f "$SOURCE_VIDEO" ]; then
    echo "ERROR: Source video not created"
    exit 1
fi

# Get source video properties
SIZE_BYTES=$(stat -c%s "$SOURCE_VIDEO" 2>/dev/null || stat -f%z "$SOURCE_VIDEO")
SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1048576" | bc)

echo "✅ Source video created: ${SIZE_MB}MB"

# Store original video info for verification using ffprobe
ffprobe -v error -show_format -show_streams -of json "$SOURCE_VIDEO" > "$INFO_FILE" 2>/dev/null || {
    echo "WARNING: Could not generate video info"
}

# Extract key properties for display
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_VIDEO" 2>/dev/null || echo "135")
RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$SOURCE_VIDEO" 2>/dev/null || echo "1920x1080")

# Create a summary file for easy reference
cat > /tmp/email_source_summary.txt <<EOF
Original Video Properties:
- File: $SOURCE_VIDEO
- Size: ${SIZE_MB}MB
- Duration: ${DURATION}s
- Resolution: ${RESOLUTION}
- Target compressed size: < 25MB
- Compression ratio needed: ~$(echo "scale=1; $SIZE_MB / 25" | bc):1
EOF

chown ga:ga "$SOURCE_VIDEO" "$INFO_FILE" /tmp/email_source_summary.txt 2>/dev/null || true

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_compress_task.log 2>&1 &"

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

echo "=== Compress for Email Task Setup Complete ==="
echo ""
echo "📧 TASK: Compress video for email sharing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat /tmp/email_source_summary.txt
echo ""
echo "📝 Instructions:"
echo "  1. Open Media → Convert/Save (or press Ctrl+R)"
echo "  2. Click 'Add' and select: $SOURCE_VIDEO"
echo "  3. Click 'Convert/Save' button"
echo "  4. In the Convert dialog:"
echo "     a. Choose a profile (e.g., 'Video - H.264 + MP3 (MP4)')"
echo "     b. OR click the wrench icon to customize settings:"
echo "        - Video Codec: H.264"
echo "        - Resolution: Scale to 720p (1280x720) or 480p (854x480)"
echo "        - Video Bitrate: ~1200-1400 kbps"
echo "        - Audio Codec: AAC or MP3"
echo "        - Audio Bitrate: 128 kbps"
echo "  5. Set destination file:"
echo "     /home/ga/Videos/compressed/email_compressed.mp4"
echo "  6. Click 'Start' to begin conversion"
echo "  7. Wait for conversion to complete (1-2 minutes)"
echo ""
echo "🎯 Goal: File size must be < 25MB with acceptable quality"
echo "💡 Tip: Lower resolution has more impact than bitrate reduction"
echo ""