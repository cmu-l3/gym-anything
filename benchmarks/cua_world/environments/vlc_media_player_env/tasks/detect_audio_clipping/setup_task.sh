#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Detect Audio Clipping Task ==="

kill_vlc ga
sleep 1

# Ensure recordings directory exists
RECORDINGS_DIR="/home/ga/Music/recordings"
mkdir -p "$RECORDINGS_DIR"
chown ga:ga "$RECORDINGS_DIR"

# Generate test audio file with intentional clipping
AUDIO_FILE="$RECORDINGS_DIR/guitar_take_01.wav"

echo "Generating audio file with clipping sections..."

# Create audio segments with different levels using ffmpeg
# Segment 1: Clean signal at -6dB (0-5 seconds)
ffmpeg -f lavfi -i "sine=frequency=196:duration=5:sample_rate=44100" \
    -af "volume=-6dB" -y "$RECORDINGS_DIR/seg1.wav" >/dev/null 2>&1

# Segment 2: Increasing level (5-10 seconds)  
ffmpeg -f lavfi -i "sine=frequency=220:duration=5:sample_rate=44100" \
    -af "volume=-2dB" -y "$RECORDINGS_DIR/seg2.wav" >/dev/null 2>&1

# Segment 3: CLIPPING - intentionally exceed 0dB (10-15 seconds)
# Generate multiple tones and mix to create clipping
ffmpeg -f lavfi -i "sine=frequency=196:duration=5:sample_rate=44100" \
    -f lavfi -i "sine=frequency=220:duration=5:sample_rate=44100" \
    -f lavfi -i "sine=frequency=247:duration=5:sample_rate=44100" \
    -filter_complex "[0][1][2]amix=inputs=3:duration=first:dropout_transition=0,volume=1.8" \
    -y "$RECORDINGS_DIR/seg3.wav" >/dev/null 2>&1

# Segment 4: Back to clean (15-20 seconds)
ffmpeg -f lavfi -i "sine=frequency=196:duration=5:sample_rate=44100" \
    -af "volume=-6dB" -y "$RECORDINGS_DIR/seg4.wav" >/dev/null 2>&1

# Concatenate segments
cat > "$RECORDINGS_DIR/concat_list.txt" <<EOF
file '$RECORDINGS_DIR/seg1.wav'
file '$RECORDINGS_DIR/seg2.wav'
file '$RECORDINGS_DIR/seg3.wav'
file '$RECORDINGS_DIR/seg4.wav'
EOF

ffmpeg -f concat -safe 0 -i "$RECORDINGS_DIR/concat_list.txt" \
    -c:a pcm_s16le -y "$AUDIO_FILE" >/dev/null 2>&1

# Cleanup temporary files
rm -f "$RECORDINGS_DIR"/seg*.wav "$RECORDINGS_DIR/concat_list.txt"

# Verify audio file was created
if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR: Failed to generate audio file"
    exit 1
fi

chown ga:ga "$AUDIO_FILE"
echo "✅ Audio file generated: $AUDIO_FILE ($(du -h "$AUDIO_FILE" | cut -f1))"

# Store ground truth for verification
cat > /tmp/clipping_ground_truth.json <<EOF
{
  "file": "guitar_take_01.wav",
  "has_clipping": true,
  "clipping_timestamps": ["0:10-0:15", "10-15"],
  "peak_level": "0.0 dBFS",
  "expected_recommendation": "NEEDS RE-RECORDING",
  "expected_answer": "YES"
}
EOF

# Launch VLC with the audio file and RC interface
echo "Launching VLC with audio file..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_clipping_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Detect Audio Clipping Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing guitar_take_01.wav"
echo "  2. Enable audio visualization:"
echo "     - Tools → Effects and Filters → Audio Effects → Visualizations"
echo "     - OR View → Visualizations (Spectrum, Scope, etc.)"
echo "     - OR View → Advanced Controls (shows level meters)"
echo "  3. Play through the file and watch for peaks hitting 0 dBFS"
echo "  4. Create analysis at: /home/ga/Music/recordings/guitar_take_01_analysis.txt"
echo "  5. Include: clipping detection (YES/NO), timestamps, peak level, recommendation"