#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Batch Audio Balance Task ==="

kill_vlc ga
sleep 1

# Create directories
RAW_DIR="/home/ga/Music/podcast_raw"
BALANCED_DIR="/home/ga/Music/podcast_balanced"

mkdir -p "$RAW_DIR"
mkdir -p "$BALANCED_DIR"
chown -R ga:ga /home/ga/Music

# Generate 4 audio files with different loudness levels
# Using ffmpeg to create test audio with specific volume levels
echo "Generating test audio files with varying loudness..."

# Segment A: Reference level (normal, -18 LUFS target)
ffmpeg -f lavfi -i "sine=frequency=440:duration=8" \
    -af "volume=0dB" \
    -codec:a libmp3lame -b:a 128k \
    "$RAW_DIR/segment_a.mp3" -y 2>/dev/null

# Segment B: Too quiet (-28 LUFS, needs +10dB boost)
ffmpeg -f lavfi -i "sine=frequency=523:duration=8" \
    -af "volume=-10dB" \
    -codec:a libmp3lame -b:a 128k \
    "$RAW_DIR/segment_b.mp3" -y 2>/dev/null

# Segment C: Too loud (-8 LUFS, needs -10dB reduction)
ffmpeg -f lavfi -i "sine=frequency=330:duration=8" \
    -af "volume=+10dB" \
    -codec:a libmp3lame -b:a 128k \
    "$RAW_DIR/segment_c.mp3" -y 2>/dev/null

# Segment D: Normal level (-17 LUFS, close to reference)
ffmpeg -f lavfi -i "sine=frequency=392:duration=8" \
    -af "volume=-1dB" \
    -codec:a libmp3lame -b:a 128k \
    "$RAW_DIR/segment_d.mp3" -y 2>/dev/null

# Verify files were created
for segment in segment_a segment_b segment_c segment_d; do
    if [ ! -f "$RAW_DIR/${segment}.mp3" ]; then
        echo "ERROR: Failed to create ${segment}.mp3"
        exit 1
    fi
done

echo "✅ Generated 4 audio segments with varying loudness"
ls -lh "$RAW_DIR"

# Store original file checksums for verification
echo "Recording original file checksums..."
md5sum "$RAW_DIR"/*.mp3 > /tmp/vlc_audio_balance_originals.md5

# Store original timestamps
stat -c "%Y %n" "$RAW_DIR"/*.mp3 > /tmp/vlc_audio_balance_timestamps.txt

# Launch VLC without opening files (let agent explore)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_audio_balance_task.log 2>&1 &"

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

echo "=== Batch Audio Balance Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Audio files are in: /home/ga/Music/podcast_raw/"
echo "     - segment_a.mp3 (reference level - normal)"
echo "     - segment_b.mp3 (too quiet - needs boosting)"
echo "     - segment_c.mp3 (too loud - needs reduction)"
echo "     - segment_d.mp3 (normal level - already good)"
echo ""
echo "  2. Listen to each file to assess volume"
echo "     - Use: Media → Open File (Ctrl+O)"
echo ""
echo "  3. For files needing adjustment:"
echo "     - Open in VLC"
echo "     - Use Media → Convert/Save (Ctrl+R)"
echo "     - OR: Tools → Effects and Filters (Ctrl+E), then convert"
echo "     - Adjust volume/gain appropriately"
echo "     - Save to: /home/ga/Music/podcast_balanced/"
echo ""
echo "  4. Goal: All output files should have similar perceived loudness"
echo "  5. IMPORTANT: Do NOT modify files in podcast_raw/ (non-destructive editing)"
echo ""
echo "  Hint: segment_b needs volume increase, segment_c needs decrease"