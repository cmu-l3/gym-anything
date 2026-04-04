#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Compatibility Issue Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
VIDEOS_DIR="/home/ga/Videos"
DOCS_DIR="/home/ga/Documents"
mkdir -p "$VIDEOS_DIR" "$DOCS_DIR"
chown -R ga:ga "$VIDEOS_DIR" "$DOCS_DIR"

# Create a test video with HEVC codec (compatibility issue)
# HEVC/H.265 is not universally supported and causes compatibility issues
PROBLEM_VIDEO="$VIDEOS_DIR/problem_upload.mp4"

echo "Creating test video with HEVC codec (this may take a moment)..."

# Check if ffmpeg supports libx265
if ! ffmpeg -codecs 2>/dev/null | grep -q libx265; then
    echo "WARNING: libx265 not available, falling back to libx264"
    # Fallback: create with H.264 but unusual profile
    ffmpeg -f lavfi -i testsrc=duration=8:size=1920x1080:rate=30 \
      -f lavfi -i sine=frequency=1000:duration=8 \
      -c:v libx264 -preset ultrafast -profile:v high444 -level 5.1 \
      -c:a aac -b:a 128k -ar 48000 -ac 2 \
      -movflags +faststart \
      "$PROBLEM_VIDEO" \
      -y 2>/dev/null || {
        echo "ERROR: Failed to create test video"
        exit 1
      }
else
    # Create with HEVC (H.265) - the actual compatibility problem
    ffmpeg -f lavfi -i testsrc=duration=8:size=1920x1080:rate=30 \
      -f lavfi -i sine=frequency=1000:duration=8 \
      -c:v libx265 -preset ultrafast -crf 28 \
      -c:a aac -b:a 128k -ar 48000 -ac 2 \
      -movflags +faststart \
      -tag:v hvc1 \
      "$PROBLEM_VIDEO" \
      -y 2>/dev/null || {
        echo "ERROR: Failed to create test video with HEVC"
        exit 1
      }
fi

# Verify file was created
if [ ! -f "$PROBLEM_VIDEO" ]; then
    echo "ERROR: Failed to create test video"
    exit 1
fi

# Set ownership
chown ga:ga "$PROBLEM_VIDEO"

echo "Test video created: $PROBLEM_VIDEO"
ls -lh "$PROBLEM_VIDEO"

# Get video info for logging
ffprobe -v error -show_entries stream=codec_name,width,height -of default=noprint_wrappers=1 "$PROBLEM_VIDEO" 2>/dev/null || true

# Launch VLC with the problematic video
echo "Launching VLC with problem video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop '$PROBLEM_VIDEO' > /tmp/vlc_diagnose_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_diagnose_task.log 2>/dev/null || true
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

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

sleep 1

echo "=== Diagnose Compatibility Issue Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing the problematic video file"
echo "  2. Open Tools → Codec Information (Ctrl+J) or Tools → Media Information (Ctrl+I)"
echo "  3. Extract and document the following technical details:"
echo "     - Video codec name (e.g., HEVC, H.265)"
echo "     - Video resolution (e.g., 1920x1080)"
echo "     - Frame rate (e.g., 30 fps)"
echo "     - Audio codec name (e.g., AAC)"
echo "     - Audio sample rate (e.g., 48000 Hz)"
echo "     - Audio channels (e.g., 2)"
echo "  4. Save findings to: /home/ga/Documents/video_diagnostic_report.txt"
echo "  5. Use any text editor (gedit, nano, etc.)"