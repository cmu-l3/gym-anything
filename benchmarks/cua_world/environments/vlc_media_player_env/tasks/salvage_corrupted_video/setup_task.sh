#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Salvage Corrupted Video Task ==="

kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos/corrupted
mkdir -p /home/ga/Videos/recovered
mkdir -p /tmp/vlc_salvage

# Generate a complete source video (30 seconds, 1280x720)
echo "Generating source video..."
ffmpeg -f lavfi -i testsrc=duration=30:size=1280x720:rate=30 \
    -f lavfi -i sine=frequency=1000:duration=30 \
    -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 128k \
    /tmp/vlc_salvage/complete_video.mp4 -y 2>/dev/null

if [ ! -f /tmp/vlc_salvage/complete_video.mp4 ]; then
    echo "ERROR: Failed to generate source video"
    exit 1
fi

# Corrupt the video by truncating it at ~75% completion
FILE_SIZE=$(stat -c%s /tmp/vlc_salvage/complete_video.mp4)
TRUNCATE_SIZE=$((FILE_SIZE * 75 / 100))

echo "Corrupting video (truncating at 75%)..."
dd if=/tmp/vlc_salvage/complete_video.mp4 \
    of=/home/ga/Videos/corrupted/interview_incomplete.mp4 \
    bs=1 count=$TRUNCATE_SIZE 2>/dev/null

# Add additional corruption - inject random bytes in the middle
# This simulates partial damage during transfer
CORRUPT_POS=$((TRUNCATE_SIZE / 2))
dd if=/dev/urandom of=/home/ga/Videos/corrupted/interview_incomplete.mp4 \
    bs=1024 count=4 seek=$((CORRUPT_POS / 1024)) conv=notrunc 2>/dev/null

# Set ownership
chown -R ga:ga /home/ga/Videos/corrupted
chown -R ga:ga /home/ga/Videos/recovered

# Ensure output directory is writable
chmod 755 /home/ga/Videos/recovered

# Store original file size for verification
echo "$FILE_SIZE" > /tmp/vlc_salvage_original_size.txt
echo "$TRUNCATE_SIZE" > /tmp/vlc_salvage_corrupted_size.txt

echo "=== Corruption complete ==="
echo "Original size: $FILE_SIZE bytes"
echo "Truncated size: $TRUNCATE_SIZE bytes"
echo "Corruption: Truncated at 75% + random data injection"

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_salvage_task.log 2>&1 &"

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

echo "=== Salvage Corrupted Video Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Input file (corrupted): /home/ga/Videos/corrupted/interview_incomplete.mp4"
echo "  2. Output file (recovered): /home/ga/Videos/recovered/interview_salvaged.mp4"
echo "  3. Use Media → Convert/Save (Ctrl+R)"
echo "  4. Add corrupted file as source"
echo "  5. Choose profile: Video - H.264 + AAC (MP4)"
echo "  6. Set destination to recovered directory"
echo "  7. Start conversion"
echo ""
echo "Note: VLC may show errors during conversion - this is expected"
echo "      It will skip damaged sections and save recoverable portions"