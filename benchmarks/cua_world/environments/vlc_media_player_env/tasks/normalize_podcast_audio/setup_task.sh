#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Normalize Podcast Audio Task ==="

kill_vlc ga
sleep 1

# Create project directories
TASK_DIR="/home/ga/podcast_project"
RAW_DIR="${TASK_DIR}/raw"
NORM_DIR="${TASK_DIR}/normalized"

mkdir -p "${RAW_DIR}" "${NORM_DIR}"

# Generate three audio files with different volume levels using ffmpeg
echo "Generating test audio files with different volumes..."

# Intro: quiet (-12 dB, then we'll add -6 dB = -18 dB total for clear difference)
# Use different frequencies to make them distinguishable
ffmpeg -f lavfi -i "sine=frequency=440:duration=10" -af "volume=-12dB" \
    -b:a 128k "${RAW_DIR}/segment_intro.mp3" -y 2>/dev/null || {
    echo "ERROR: ffmpeg failed to generate intro"
    exit 1
}

# Interview: reference (-6 dB)
ffmpeg -f lavfi -i "sine=frequency=523:duration=10" -af "volume=-6dB" \
    -b:a 128k "${RAW_DIR}/segment_interview.mp3" -y 2>/dev/null || {
    echo "ERROR: ffmpeg failed to generate interview"
    exit 1
}

# Outro: louder (-3 dB)
ffmpeg -f lavfi -i "sine=frequency=349:duration=10" -af "volume=-3dB" \
    -b:a 128k "${RAW_DIR}/segment_outro.mp3" -y 2>/dev/null || {
    echo "ERROR: ffmpeg failed to generate outro"
    exit 1
}

# Set ownership
chown -R ga:ga "${TASK_DIR}"

echo "✅ Podcast audio segments created:"
ls -lh "${RAW_DIR}/"

# Display original audio levels for reference
echo ""
echo "Original audio levels (for reference):"
for file in "${RAW_DIR}"/*.mp3; do
    filename=$(basename "$file")
    echo -n "  $filename: "
    ffmpeg -i "$file" -af "volumedetect" -f null /dev/null 2>&1 | grep "max_volume" | awk '{print $5, $6}' || echo "unknown"
done

# Launch VLC
echo ""
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_normalize_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_normalize_task.log || true
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

echo ""
echo "=== Normalize Podcast Audio Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "You have three podcast segments with inconsistent volumes:"
echo ""
echo "Source files (in /home/ga/podcast_project/raw/):"
echo "  • segment_intro.mp3      (too quiet)"
echo "  • segment_interview.mp3  (reference level)"
echo "  • segment_outro.mp3      (too loud)"
echo ""
echo "Your goal: Normalize all three to have consistent peak levels"
echo ""
echo "Recommended approach using VLC command line:"
echo "  1. Open terminal (Ctrl+Alt+T)"
echo "  2. Navigate: cd /home/ga/podcast_project/raw"
echo "  3. For each file, run:"
echo "     cvlc <file>.mp3 --audio-filter normvol --norm-max-level 0.9 \\"
echo "       --sout='#transcode{acodec=mp3,ab=128}:std{access=file,mux=mp3,dst=../normalized/normalized_<file>.mp3}' \\"
echo "       vlc://quit"
echo ""
echo "Alternative: Use GUI (Media → Convert/Save) with normalization"
echo ""
echo "Output location: /home/ga/podcast_project/normalized/"
echo "Output naming: normalized_segment_intro.mp3, etc."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"