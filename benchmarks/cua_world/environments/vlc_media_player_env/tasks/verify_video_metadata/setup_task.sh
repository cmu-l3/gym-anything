#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Video Metadata Task ==="

kill_vlc ga
sleep 1

# Create verify directory
mkdir -p /home/ga/Videos/verify
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Videos/verify
chown -R ga:ga /home/ga/Documents

# Create a sample video with specific metadata
# This simulates a "user-submitted" video with embedded metadata that contradicts the claim

VIDEO_PATH="/home/ga/Videos/verify/user_submitted_protest.mp4"

# Calculate date 30 days ago (to contradict "yesterday" claim)
CREATION_DATE=$(date -d '30 days ago' '+%Y-%m-%d %H:%M:%S')

echo "Creating sample video with embedded metadata..."

# Create a simple 10-second test video with color bars and embedded metadata
su - ga -c "ffmpeg -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 \
    -f lavfi -i sine=frequency=1000:duration=10 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -c:a aac -b:a 128k \
    -metadata creation_time='${CREATION_DATE}' \
    -metadata title='Protest Footage Archive' \
    -metadata comment='Recorded on Generic Camera Model X' \
    -metadata artist='Unknown' \
    -metadata encoder='Lavf58.29.100' \
    '${VIDEO_PATH}' -y 2>/tmp/ffmpeg_metadata_creation.log"

if [ ! -f "$VIDEO_PATH" ]; then
    echo "ERROR: Failed to create sample video"
    cat /tmp/ffmpeg_metadata_creation.log
    exit 1
fi

echo "✅ Sample video created: $VIDEO_PATH"

# Verify the video has the expected metadata
echo "Verifying embedded metadata..."
ffprobe -v quiet -show_entries format_tags=creation_time,title,comment,encoder -of default=noprint_wrappers=1 "$VIDEO_PATH" > /tmp/embedded_metadata.txt
cat /tmp/embedded_metadata.txt

# Create a readme file with the "claim" for context
cat > /home/ga/Videos/verify/README.txt <<EOF
VIDEO VERIFICATION REQUEST
========================

Source Claim:
"This video was shot YESTERDAY on an iPhone 14 Pro at the downtown protest."

Your Task:
Extract all metadata from user_submitted_protest.mp4 to verify this claim.
Use VLC Media Player's Media Information dialog (Tools -> Media Information).

Document your findings in: /home/ga/Documents/video_verification_report.txt

Key questions to answer:
1. What is the actual creation/encoding date?
2. What codec and resolution was used?
3. What camera/device created this video?
4. Does the metadata support or contradict the source's claim?
EOF

chown ga:ga /home/ga/Videos/verify/README.txt

# Launch VLC with the video loaded (but paused)
echo "Launching VLC with video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$VIDEO_PATH' > /tmp/vlc_metadata_task.log 2>&1 &"

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

echo "=== Verify Video Metadata Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Video loaded: /home/ga/Videos/verify/user_submitted_protest.mp4"
echo "  2. Source claims: 'Shot yesterday on iPhone 14 Pro'"
echo "  3. Open Tools -> Media Information (Ctrl+I)"
echo "  4. Navigate through tabs:"
echo "     - General Information"
echo "     - Codec Information"
echo "     - Metadata"
echo "  5. Extract ALL available metadata"
echo "  6. Create report: /home/ga/Documents/video_verification_report.txt"
echo "  7. Document: codec, resolution, duration, dates, encoder, etc."
echo ""
echo "  See /home/ga/Videos/verify/README.txt for full context"