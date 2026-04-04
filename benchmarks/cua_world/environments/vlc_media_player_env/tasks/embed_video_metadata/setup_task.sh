#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Embed Video Metadata Task ==="

kill_vlc ga
sleep 1

# Create directory structure
TASK_DIR="/home/ga/Videos/metadata_test"
mkdir -p "$TASK_DIR"

# Generate a test video file with NO metadata (clean slate)
echo "Generating test video with blank metadata..."
ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=30 \
       -f lavfi -i sine=frequency=1000:duration=30 \
       -c:v libx264 -preset ultrafast -crf 28 -c:a aac -b:a 128k \
       -metadata title="" \
       -metadata artist="" \
       -metadata description="" \
       -metadata copyright="" \
       -metadata comment="" \
       -y "$TASK_DIR/documentary.mp4" > /tmp/metadata_setup.log 2>&1

# Verify file was created
if [ ! -f "$TASK_DIR/documentary.mp4" ]; then
    echo "ERROR: Failed to create test video"
    cat /tmp/metadata_setup.log
    exit 1
fi

# Verify initial metadata state (should be empty)
echo "Verifying initial metadata state..."
ffprobe -v error -show_entries format_tags=title,artist,description,copyright \
        -of default=noprint_wrappers=1:nokey=1 \
        "$TASK_DIR/documentary.mp4" > /tmp/metadata_initial.txt 2>&1 || true

echo "Initial metadata:"
cat /tmp/metadata_initial.txt || echo "(empty or minimal)"

# Set permissions
chown -R ga:ga "$TASK_DIR"
chmod -R 755 "$TASK_DIR"

# Launch VLC (without file - agent needs to open it)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_metadata_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_metadata_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Embed Video Metadata Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open the video file: /home/ga/Videos/metadata_test/documentary.mp4"
echo "     (Use Media → Open File or Ctrl+O)"
echo "  2. Open Media Information dialog: Tools → Media Information (Ctrl+I)"
echo "  3. In the 'General' tab, edit the metadata fields:"
echo "     - Title: Urban Wildlife Behavior Study"
echo "     - Artist: Dr. Emily Chen"
echo "     - Description: Observational study of raccoon populations in metropolitan areas, filmed 2023-2024"
echo "     - Copyright: Creative Commons BY-SA 4.0"
echo "  4. Click 'Save Metadata' button (important!)"
echo "  5. Close the dialog"
echo ""
echo "Test file created: $TASK_DIR/documentary.mp4"