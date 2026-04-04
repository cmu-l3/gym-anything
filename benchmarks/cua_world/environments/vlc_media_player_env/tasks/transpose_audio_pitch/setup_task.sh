#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Transpose Audio Pitch Task ==="

kill_vlc ga
sleep 1

# Ensure Music directory exists
mkdir -p /home/ga/Music
chown ga:ga /home/ga/Music

# Generate practice audio track if it doesn't exist
PRACTICE_TRACK="/home/ga/Music/practice_track.mp3"
if [ ! -f "$PRACTICE_TRACK" ]; then
    echo "Generating practice audio track..."
    # Create a musical tone sequence (E major chord tones: E, G#, B)
    # This simulates a practice track in E major
    ffmpeg -f lavfi -i "sine=frequency=329.63:duration=10" \
        -f lavfi -i "sine=frequency=415.30:duration=10" \
        -f lavfi -i "sine=frequency=493.88:duration=10" \
        -filter_complex "[0:a][1:a][2:a]amix=inputs=3:duration=longest:normalize=0" \
        -b:a 192k -y "$PRACTICE_TRACK" > /tmp/ffmpeg_audio_gen.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to generate practice track"
        cat /tmp/ffmpeg_audio_gen.log
        exit 1
    fi
    
    chown ga:ga "$PRACTICE_TRACK"
    echo "✅ Practice track generated: $PRACTICE_TRACK"
fi

# Reset VLC audio effects configuration
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc
chown ga:ga /home/ga/.config/vlc

if [ -f "$VLC_RC" ]; then
    # Remove any existing pitch/audio filter settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^pitch-shift=/d' "$VLC_RC"
    sed -i '/^scaletempo-stride=/d' "$VLC_RC"
    sed -i '/^scaletempo-overlap=/d' "$VLC_RC"
    sed -i '/^audiorate=/d' "$VLC_RC"
    echo "Audio effects reset in config"
fi

# Launch VLC with RC interface and the practice track (looped)
echo "Launching VLC with RC interface and practice track..."
su - ga -c "DISPLAY=:1 vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$PRACTICE_TRACK' > /tmp/vlc_pitch_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_pitch_task.log
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
    echo "RC interface not ready, waiting... ($i/10)"
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

# Give VLC a moment to stabilize
sleep 2

echo "=== Transpose Audio Pitch Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a practice track (musical tones in E major)"
echo "  2. Open Effects and Filters: Tools → Effects and Filters (Ctrl+E)"
echo "  3. Go to Audio Effects tab"
echo "  4. Enable Audio Effects checkbox"
echo "  5. Find Pitch adjustment slider or Spatializer with pitch control"
echo "  6. Set pitch shift to -3 semitones (or -300 cents)"
echo "  7. Verify playback speed remains 1.0x (not affected)"
echo "  8. Close dialog to save settings"
echo ""
echo "Note: The pitch slider may be labeled 'Pitch shift' or under advanced audio effects"