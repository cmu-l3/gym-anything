#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Media Specifications Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Videos/submission
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos/submission
chown -R ga:ga /home/ga/Documents

# Generate test video with specific specifications
# Resolution: 1920x1080, Codec: H.264, Audio: AAC, Duration: 30 seconds
VIDEO_FILE="/home/ga/Videos/submission/contributor_video.mp4"

echo "Generating test video with specifications: 1920x1080, H.264, AAC..."

# Create a test video with color bars and test pattern for visual interest
ffmpeg -f lavfi -i "testsrc=duration=30:size=1920x1080:rate=30" \
       -f lavfi -i "sine=frequency=440:duration=30" \
       -c:v libx264 -preset ultrafast -profile:v high -level 4.0 \
       -c:a aac -b:a 128k \
       -pix_fmt yuv420p \
       -movflags +faststart \
       "$VIDEO_FILE" \
       -y -loglevel error

if [ ! -f "$VIDEO_FILE" ]; then
    echo "ERROR: Failed to create test video"
    exit 1
fi

# Verify video was created with correct specs
echo "Verifying video specifications..."
VIDEO_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=p=0 "$VIDEO_FILE")
echo "Video info: $VIDEO_INFO"

# Set ownership
chown ga:ga "$VIDEO_FILE"

# Create a template file (optional, for guidance)
cat > /home/ga/Documents/video_specs_template.txt <<EOF
Video Specification Verification Report
========================================

File: contributor_video.mp4

Technical Requirements:
- Resolution: 1920x1080 (required)
- Video Codec: H.264 (required)
- Audio Track: Must be present

Verification Results:
[To be filled by verifier]

Status: [APPROVED/REJECTED]
EOF

chown ga:ga /home/ga/Documents/video_specs_template.txt

# Launch VLC with the video file
echo "Launching VLC with contributor video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$VIDEO_FILE' > /tmp/vlc_mediainfo_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_mediainfo_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (standard pattern)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
echo "Focusing VLC window..."
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Give video time to load
sleep 2

echo "=== Verify Media Specifications Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "=========================================="
echo "You are a content manager verifying a video submission."
echo ""
echo "Requirements to verify:"
echo "  - Resolution: 1920x1080 (1080p)"
echo "  - Video Codec: H.264"
echo "  - Audio: Must have audio track"
echo ""
echo "Steps:"
echo "  1. Video is already open in VLC (contributor_video.mp4)"
echo "  2. Access Media Information:"
echo "     - Press Ctrl+I (or Ctrl+J)"
echo "     - OR: Tools → Media Information"
echo "  3. Check the Codec Details tab for specifications"
echo "  4. Create verification document at:"
echo "     /home/ga/Documents/video_specs_verified.txt"
echo "  5. Document must include:"
echo "     - Resolution: 1920x1080 ✓"
echo "     - Video Codec: H.264 ✓"
echo "     - Audio: Present ✓"
echo "     - Status: APPROVED"
echo ""
echo "Optional: You can use the template file as reference:"
echo "  /home/ga/Documents/video_specs_template.txt"
echo "=========================================="