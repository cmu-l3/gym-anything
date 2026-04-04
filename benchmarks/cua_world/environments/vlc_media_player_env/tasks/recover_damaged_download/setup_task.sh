#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Recover Damaged Download Task ==="

kill_vlc ga
sleep 1

# Setup directories
WORKSPACE="/home/ga/Videos"
DAMAGED_DIR="${WORKSPACE}/damaged"
RECOVERED_DIR="${WORKSPACE}/recovered"

mkdir -p "${DAMAGED_DIR}" "${RECOVERED_DIR}"
chown -R ga:ga "${DAMAGED_DIR}" "${RECOVERED_DIR}"

echo "Creating simulated damaged video file..."

# First, create a complete long-form test video (120 minutes = 7200 seconds)
# We'll use a shorter version for faster testing (use 10 minutes but pretend it's 120)
# To simulate a lecture, add timestamps and simple content
DURATION=600  # 10 minutes for faster testing, scale expectations accordingly

echo "Generating base video file..."

# Create test video with clear visual timestamp overlay
ffmpeg -f lavfi -i testsrc=duration=${DURATION}:size=1280x720:rate=30 \
       -f lavfi -i sine=frequency=440:duration=${DURATION} \
       -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:\
text='Time\: %{pts\:hms}':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=80:\
box=1:boxcolor=black@0.7:boxborderw=5" \
       -c:v libx264 -preset fast -crf 23 \
       -c:a aac -b:a 128k \
       -movflags +faststart \
       -y "${DAMAGED_DIR}/complete_temp.mp4" 2>/tmp/vlc_recovery_setup.log

if [ ! -f "${DAMAGED_DIR}/complete_temp.mp4" ]; then
    echo "ERROR: Failed to create base video"
    cat /tmp/vlc_recovery_setup.log
    exit 1
fi

echo "Base video created successfully"

# Get size of complete file
COMPLETE_SIZE=$(stat -c%s "${DAMAGED_DIR}/complete_temp.mp4" 2>/dev/null || stat -f%z "${DAMAGED_DIR}/complete_temp.mp4")
echo "Complete file size: ${COMPLETE_SIZE} bytes"

# Calculate 85% of file size (simulating interrupted download at 85%)
PARTIAL_SIZE=$(echo "$COMPLETE_SIZE * 0.85" | bc | cut -d. -f1)
echo "Truncating to: ${PARTIAL_SIZE} bytes (85% of original)"

# Truncate file to simulate incomplete download
dd if="${DAMAGED_DIR}/complete_temp.mp4" \
   of="${DAMAGED_DIR}/lecture_recording.mp4" \
   bs=1M \
   count=$((PARTIAL_SIZE / 1048576 + 1)) \
   iflag=fullblock 2>/tmp/vlc_truncate.log

# More precise truncation
truncate -s "${PARTIAL_SIZE}" "${DAMAGED_DIR}/lecture_recording.mp4"

# Verify damaged file was created
if [ ! -f "${DAMAGED_DIR}/lecture_recording.mp4" ]; then
    echo "ERROR: Failed to create damaged file"
    exit 1
fi

DAMAGED_SIZE=$(stat -c%s "${DAMAGED_DIR}/lecture_recording.mp4" 2>/dev/null || stat -f%z "${DAMAGED_DIR}/lecture_recording.mp4")
PERCENT_COMPLETE=$(echo "scale=1; $DAMAGED_SIZE * 100 / $COMPLETE_SIZE" | bc)

echo "✅ Damaged file created:"
echo "   Path: ${DAMAGED_DIR}/lecture_recording.mp4"
echo "   Size: ${DAMAGED_SIZE} bytes (${PERCENT_COMPLETE}% of original)"
echo "   Expected recoverable: ~7-8 minutes"

# Clean up complete file
rm -f "${DAMAGED_DIR}/complete_temp.mp4"

# Store recovery metadata for verification
cat > /tmp/vlc_recovery_info.txt <<EOF
original_size=${COMPLETE_SIZE}
damaged_size=${DAMAGED_SIZE}
duration_original=${DURATION}
expected_recovered_min=360
expected_recovered_max=540
EOF

echo "Metadata stored in /tmp/vlc_recovery_info.txt"

# Set proper permissions
chown -R ga:ga "${WORKSPACE}"
chmod -R 755 "${WORKSPACE}"

# Launch VLC without any file (let agent navigate to conversion)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_recovery_task.log 2>&1 &"

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

echo "=== Recover Damaged Download Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Damaged file location: /home/ga/Videos/damaged/lecture_recording.mp4"
echo "  2. Target output: /home/ga/Videos/recovered/lecture_recovered.mp4"
echo ""
echo "💡 Recommended approach:"
echo "  • Use Media → Convert/Save (Ctrl+R)"
echo "  • Add the damaged file as source"
echo "  • Choose an output format (e.g., H.264 + MP3)"
echo "  • Set destination path"
echo "  • Start conversion (VLC will stop at corrupted portion)"
echo ""
echo "⚠️  The file is intentionally corrupted - VLC may show errors, this is expected"
echo "🎯 Goal: Extract ~7-8 minutes of clean, playable video"