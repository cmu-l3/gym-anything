#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adjust Stereo Balance Task ==="

kill_vlc ga
sleep 1

# Reset VLC audio effects configuration to defaults
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing audio effect settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^spatializer-/d' "$VLC_RC"
    sed -i '/^headphone-/d' "$VLC_RC"
    sed -i '/^param-eq-/d' "$VLC_RC"
    sed -i '/^compressor-/d' "$VLC_RC"
    sed -i '/^audio-visual=/d' "$VLC_RC"
    sed -i '/^equalizer-/d' "$VLC_RC"
    echo "Audio effects reset to defaults"
fi

# Ensure audio sample exists, if not create one
AUDIO_SAMPLE="/home/ga/Music/audiobook_sample.mp3"
if [ ! -f "$AUDIO_SAMPLE" ]; then
    echo "Creating audiobook sample audio file..."
    # Create a 2-minute stereo audio file with distinct L/R channels
    # Left channel: 300Hz tone, Right channel: 500Hz tone
    ffmpeg -f lavfi -i "sine=frequency=300:duration=120" \
           -f lavfi -i "sine=frequency=500:duration=120" \
           -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" \
           -map "[a]" -ac 2 -b:a 192k -y "$AUDIO_SAMPLE" > /tmp/ffmpeg_audio_gen.log 2>&1 || {
        echo "ERROR: Failed to generate audio sample"
        cat /tmp/ffmpeg_audio_gen.log
        exit 1
    }
    chown ga:ga "$AUDIO_SAMPLE"
    echo "✅ Audiobook sample created: $AUDIO_SAMPLE"
fi

# Launch VLC with audio file and RC interface
echo "Launching VLC with audio sample..."
su - ga -c "DISPLAY=:1 vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_SAMPLE' > /tmp/vlc_balance_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_balance_task.log || true
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

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for audio to start playing
sleep 2

echo "=== Adjust Stereo Balance Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. You have asymmetric hearing (left ear is weak) or damaged left headphone"
echo "  2. The audiobook is currently playing with centered stereo balance"
echo "  3. Shift audio balance significantly to RIGHT channel so you can hear better"
echo "  4. Options to try:"
echo "     a) Tools → Effects and Filters (Ctrl+E) → Audio Effects → Spatializer"
echo "     b) Tools → Effects and Filters → Audio Effects → Advanced"
echo "     c) Tools → Preferences → Show All → Audio → Filters"
echo "  5. Goal: Emphasize right channel by ≥60% (reduce left channel significantly)"
echo "  6. Make sure to ENABLE the effect checkbox and SAVE settings"
echo ""
echo "  Audio file: $AUDIO_SAMPLE (L=300Hz, R=500Hz for testing)"