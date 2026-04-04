#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enhance Lecture Audio Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Music
chown -R ga:ga /home/ga/Music

# Generate poor-quality lecture audio with low-frequency rumble
AUDIO_FILE="/home/ga/Music/lecture_recording.mp3"
TMP_DIR="/tmp/lecture_audio_gen_$$"

echo "Generating muddy lecture audio with rumble..."
mkdir -p "$TMP_DIR"

# Generate base speech-like audio (combination of frequencies simulating speech)
# Use pink noise filtered to speech range with formants
ffmpeg -f lavfi -i "sine=frequency=200:duration=15" \
  -f lavfi -i "sine=frequency=500:duration=15" \
  -f lavfi -i "sine=frequency=800:duration=15" \
  -f lavfi -i "sine=frequency=1500:duration=15" \
  -f lavfi -i "sine=frequency=2500:duration=15" \
  -filter_complex "[0][1][2][3][4]amix=inputs=5:duration=first:weights=1 0.7 0.6 0.5 0.4[speech];
    [speech]highpass=f=180,lowpass=f=6000[filtered];
    [filtered]volume=-12dB[quiet]" \
  -map "[quiet]" -ar 22050 -ac 1 -b:a 128k \
  "$TMP_DIR/clean_speech.mp3" -y 2>/dev/null

# Generate low-frequency rumble (HVAC/environment noise)
ffmpeg -f lavfi -i "sine=frequency=60:duration=15" \
  -f lavfi -i "sine=frequency=90:duration=15" \
  -f lavfi -i "sine=frequency=120:duration=15" \
  -filter_complex "[0][1][2]amix=inputs=3:duration=first[rumble];
    [rumble]volume=-8dB[loud_rumble]" \
  -map "[loud_rumble]" -ar 22050 -ac 1 \
  "$TMP_DIR/rumble.mp3" -y 2>/dev/null

# Mix speech with rumble to create muddy audio
ffmpeg -i "$TMP_DIR/clean_speech.mp3" -i "$TMP_DIR/rumble.mp3" \
  -filter_complex "[0][1]amix=inputs=2:duration=first:weights=0.5 0.9[mixed];
    [mixed]volume=-2dB,highpass=f=40[output]" \
  -map "[output]" -ar 22050 -ac 1 -b:a 128k \
  "$AUDIO_FILE" -y 2>/dev/null

# Cleanup temporary files
rm -rf "$TMP_DIR"

# Set proper ownership
chown ga:ga "$AUDIO_FILE"

echo "✅ Generated lecture audio: $AUDIO_FILE ($(du -h "$AUDIO_FILE" | cut -f1))"

# Reset VLC equalizer settings to default
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p "$(dirname "$VLC_RC")"
chown ga:ga "$(dirname "$VLC_RC")"

if [ -f "$VLC_RC" ]; then
    # Remove any existing equalizer settings
    sed -i '/^equalizer/d' "$VLC_RC"
    sed -i '/^audio-filter=/d' "$VLC_RC"
    echo "Equalizer settings reset"
fi

# Launch VLC with audio file and RC interface for potential querying
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_equalizer_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_equalizer_task.log 2>/dev/null || true
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

# Click on center of screen to select desktop (standard procedure)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Enhance Lecture Audio Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is now playing lecture audio with poor quality"
echo "  2. Open Tools → Effects and Filters (Ctrl+E)"
echo "  3. Go to Audio Effects tab → Equalizer"
echo "  4. Enable the Equalizer checkbox"
echo "  5. Reduce low frequency bands (60Hz, 170Hz, 310Hz) by -4 to -6 dB"
echo "  6. Boost mid-range bands (1kHz, 3kHz, 6kHz) by +4 to +6 dB"
echo "  7. Close the dialog to save settings"
echo ""
echo "📊 Target adjustments:"
echo "  • 60Hz:  -5 dB (reduce rumble)"
echo "  • 170Hz: -4 dB (reduce rumble)"  
echo "  • 310Hz: -2 dB (reduce rumble)"
echo "  • 1kHz:  +5 dB (boost speech clarity)"
echo "  • 3kHz:  +6 dB (boost speech clarity)"
echo "  • 6kHz:  +4 dB (boost speech presence)"
echo ""
echo "Audio file: $AUDIO_FILE"