#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Partial Download Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Downloads
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Downloads
chown -R ga:ga /home/ga/Documents

# Create partial video file
echo "Creating partial video file (this may take 30-40 seconds)..."

PARTIAL_FILE="/home/ga/Downloads/wildlife_documentary.partial.mp4"

# First, create a complete 60-minute video (using fast settings)
# Using testsrc2 pattern for faster generation
COMPLETE_VIDEO="/tmp/complete_wildlife_doc.mp4"

if [ ! -f "$COMPLETE_VIDEO" ]; then
    echo "Generating complete 60-minute video..."
    ffmpeg -f lavfi -i testsrc2=duration=3600:size=1280x720:rate=10 \
           -f lavfi -i sine=frequency=440:duration=3600 \
           -c:v libx264 -preset ultrafast -tune zerolatency \
           -c:a aac -b:a 128k \
           -t 3600 \
           "$COMPLETE_VIDEO" > /tmp/ffmpeg_generate.log 2>&1 || {
        echo "ERROR: Failed to generate complete video"
        cat /tmp/ffmpeg_generate.log
        exit 1
    }
    echo "✅ Complete video generated"
else
    echo "✅ Using existing complete video"
fi

# Truncate to 35 minutes (2100 seconds) of playable content
echo "Truncating to 35 minutes playable..."
ffmpeg -i "$COMPLETE_VIDEO" -t 2100 -c copy "$PARTIAL_FILE" > /tmp/ffmpeg_truncate.log 2>&1 || {
    echo "ERROR: Failed to truncate video"
    cat /tmp/ffmpeg_truncate.log
    exit 1
}

# Verify partial file was created
if [ ! -f "$PARTIAL_FILE" ]; then
    echo "ERROR: Partial file not created"
    exit 1
fi

FILE_SIZE=$(du -h "$PARTIAL_FILE" | cut -f1)
echo "✅ Partial file created: $PARTIAL_FILE (size: $FILE_SIZE)"

# Get actual video info for verification
ACTUAL_DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$PARTIAL_FILE" 2>/dev/null || echo "0")
echo "Partial file actual duration: $(printf '%.0f' $ACTUAL_DURATION) seconds (~$(printf '%.0f' $(echo "$ACTUAL_DURATION / 60" | bc)) minutes)"

# Store ground truth for verifier
echo "$ACTUAL_DURATION" > /tmp/partial_video_ground_truth.txt

chown ga:ga "$PARTIAL_FILE"

# Launch VLC with the partial file (don't auto-play)
echo "Launching VLC with partial file..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --start-paused '$PARTIAL_FILE' > /tmp/vlc_partial_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_partial_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 360 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Verify Partial Download Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "  A user downloaded 'wildlife_documentary.mp4' over spotty WiFi."
echo "  Download shows ~45% complete. User needs to know:"
echo "    - Can I watch anything now?"
echo "    - How much is actually playable?"
echo "    - Is the file corrupted or just incomplete?"
echo ""
echo "📋 YOUR TASK:"
echo "  1. Open VLC (already launched with the partial file)"
echo "  2. Test playback at various timestamps (use binary search)"
echo "  3. Find where the file becomes unplayable"
echo "  4. Check VLC Messages (Tools → Messages) for errors"
echo "  5. Create report at: /home/ga/Documents/partial_download_report.txt"
echo ""
echo "📄 REPORT MUST INCLUDE:"
echo "  - Reported Duration (what VLC shows)"
echo "  - Playable Duration (what you tested)"
echo "  - File Status (incomplete/corrupted)"
echo "  - Recommendation (continue download / restart)"
echo "  - Testing methodology notes"
echo ""
echo "⚡ TIP: Use binary search - seek to 50%, then 25% or 75% depending on result"