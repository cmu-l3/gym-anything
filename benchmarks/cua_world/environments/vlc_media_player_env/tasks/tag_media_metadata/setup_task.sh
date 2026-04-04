#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Tag Media Metadata Task ==="

kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Generate a sample video file with NO metadata
# We'll create a short 10-second test video with color bars and audio
echo "Generating concert recording video without metadata..."

su - ga << 'EOF'
cd /home/ga/Videos

# Generate a simple 10-second test video with color bars and sine wave audio
# Explicitly strip all metadata using -map_metadata -1
ffmpeg -f lavfi -i testsrc=duration=10:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=440:duration=10 \
       -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
       -c:a aac -b:a 128k \
       -map_metadata -1 \
       -fflags +bitexact \
       -movflags +faststart \
       concert_recording.mp4 -y 2>/dev/null

# Verify file was created and has no metadata
if [ ! -f concert_recording.mp4 ]; then
    echo "ERROR: Failed to create concert_recording.mp4"
    exit 1
fi

# Check file size
FILE_SIZE=$(stat -f%z concert_recording.mp4 2>/dev/null || stat -c%s concert_recording.mp4 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -lt 10000 ]; then
    echo "ERROR: Video file too small (${FILE_SIZE} bytes)"
    exit 1
fi

echo "Video file created: concert_recording.mp4"
echo "File size: $(du -h concert_recording.mp4 | cut -f1)"

# Verify no metadata exists
METADATA_CHECK=$(ffprobe -v error -show_entries format_tags -of json concert_recording.mp4 2>/dev/null || echo "{}")
echo "Initial metadata: $METADATA_CHECK"

EOF

# Verify the file exists
if [ ! -f /home/ga/Videos/concert_recording.mp4 ]; then
    echo "ERROR: concert_recording.mp4 was not created"
    exit 1
fi

# Launch VLC with the video file loaded
echo "Launching VLC with concert recording..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused /home/ga/Videos/concert_recording.mp4 > /tmp/vlc_metadata_task.log 2>&1 &"

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

echo "=== Tag Media Metadata Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing concert_recording.mp4"
echo "  2. Open Media Information dialog: Tools → Media Information (Ctrl+I)"
echo "  3. Go to the 'Metadata' tab"
echo "  4. Fill in the following metadata fields:"
echo "     - Title: Live at The Roxy Theatre"
echo "     - Artist: The Midnight Riders"
echo "     - Album: 2024 North American Tour"
echo "     - Date: 2024-03-15"
echo "     - Genre: Rock"
echo "     - Description: Opening night performance featuring extended guitar solos and two-song encore"
echo "     - Copyright: Personal Recording - Non-Commercial Use"
echo "  5. Close the dialog to save changes"
echo "  6. Close VLC (Ctrl+Q) to ensure metadata is written"