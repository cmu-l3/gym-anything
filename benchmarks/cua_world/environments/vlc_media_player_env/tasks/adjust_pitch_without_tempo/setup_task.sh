#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adjust Pitch Without Tempo Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Paths
MUSIC_DIR="/home/ga/Music"
AUDIO_FILE="$MUSIC_DIR/practice_song.mp3"
VLC_RC="/home/ga/.config/vlc/vlcrc"

# Ensure Music directory exists
mkdir -p "$MUSIC_DIR"
chown ga:ga "$MUSIC_DIR"

# Generate sample audio file (30-second rock-style audio simulating E♭ tuning)
echo "Generating practice audio file..."

if [ ! -f "$AUDIO_FILE" ]; then
    # Create three 10-second segments with different frequencies
    # Simulating E♭ power chord: E♭=311Hz, B♭=466Hz, E♭=622Hz
    # Mix them together to create a more realistic sound
    ffmpeg -y -f lavfi \
        -i "sine=frequency=311:duration=30" \
        -i "sine=frequency=466:duration=30" \
        -i "sine=frequency=622:duration=30" \
        -filter_complex "[0:a][1:a][2:a]amix=inputs=3:duration=longest:normalize=0,volume=0.3" \
        -codec:a libmp3lame -b:a 192k \
        "$AUDIO_FILE" \
        2>/tmp/ffmpeg_setup_pitch.log || {
        echo "ERROR: Failed to generate audio file"
        cat /tmp/ffmpeg_setup_pitch.log
        exit 1
    }
    
    chown ga:ga "$AUDIO_FILE"
    echo "✅ Audio file generated: $AUDIO_FILE"
else
    echo "✅ Audio file already exists: $AUDIO_FILE"
fi

# Reset VLC configuration to defaults for audio filters
echo "Resetting VLC audio filter configuration..."

# Ensure VLC config directory exists
mkdir -p /home/ga/.config/vlc
chown -R ga:ga /home/ga/.config/vlc

if [ -f "$VLC_RC" ]; then
    # Remove any existing pitch/audio filter settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^pitch-shift=/d' "$VLC_RC"
    sed -i '/^scaletempo-pitch=/d' "$VLC_RC"
    sed -i '/^pitch-semitones=/d' "$VLC_RC"
    sed -i '/^scaletempo/d' "$VLC_RC"
    sed -i '/^rate=/d' "$VLC_RC"
    sed -i '/^speed=/d' "$VLC_RC"
    echo "VLC audio filters reset"
else
    # Create minimal vlcrc if it doesn't exist
    cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0

[core]
audio-volume=256
EOF
    chown ga:ga "$VLC_RC"
    echo "VLC config initialized"
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with audio file..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_pitch_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_pitch_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_pitch_task.log
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    echo "RC interface not ready (attempt $i/10)..."
    sleep 1
done

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (WID: $wid)"
fi

# Wait for VLC to fully render
sleep 2

echo "=== Adjust Pitch Without Tempo Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is now playing practice_song.mp3 (simulated E♭ tuning)"
echo "  2. Open Effects dialog: Tools → Effects and Filters (or press Ctrl+E)"
echo "  3. Go to Audio Effects tab"
echo "  4. Look for 'Pitch shifter' or similar audio effect"
echo "  5. Enable the pitch adjustment checkbox/filter"
echo "  6. Set pitch shift to +1 semitone (or +100 cents)"
echo "  7. Verify playback speed remains at 1.0x"
echo "  8. Close dialog to save settings"
echo ""
echo "🎸 Context: A guitarist in standard tuning needs to transpose this"
echo "   E♭-tuned recording up by one semitone to match their instrument."