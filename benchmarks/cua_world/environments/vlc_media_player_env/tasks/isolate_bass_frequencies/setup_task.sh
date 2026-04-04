#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Isolate Bass Frequencies Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Reset VLC equalizer settings to ensure clean state
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing equalizer settings
    sed -i '/^equalizer-/d' "$VLC_RC"
    echo "Equalizer settings cleared"
fi

# Ensure we have a music file with bass
MUSIC_FILE="/home/ga/Music/bass_practice.mp3"

# If bass practice file doesn't exist, use sample audio or download one
if [ ! -f "$MUSIC_FILE" ]; then
    echo "Bass practice track not found, using sample audio..."
    MUSIC_FILE="/home/ga/Music/sample_audio.mp3"
    
    # If sample audio doesn't exist either, create a simple one or download
    if [ ! -f "$MUSIC_FILE" ]; then
        echo "Creating bass-heavy test track..."
        # Use ffmpeg to generate a simple bass-heavy tone for testing
        # This creates a 30-second track with 100Hz sine wave (bass tone)
        ffmpeg -f lavfi -i "sine=frequency=100:duration=30" -f lavfi -i "sine=frequency=200:duration=30" \
               -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest" \
               -ar 44100 -ac 2 -b:a 192k "$MUSIC_FILE" -y 2>/dev/null || {
            echo "ERROR: Could not create test audio file"
            # Fallback: just use any existing audio/video file
            MUSIC_FILE="/home/ga/Videos/sample_video.mp4"
        }
    fi
fi

if [ ! -f "$MUSIC_FILE" ]; then
    echo "ERROR: No music file available for task"
    exit 1
fi

echo "Using music file: $MUSIC_FILE"

# Launch VLC with the music file, looping
echo "Launching VLC with music track..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$MUSIC_FILE' > /tmp/vlc_bass_eq_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_bass_eq_task.log
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
    echo "RC interface not ready, waiting..."
    sleep 1
done

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Give UI a moment to fully render
sleep 2

echo "=== Isolate Bass Frequencies Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is playing a music track in loop mode"
echo "  2. Open Tools → Effects and Filters (or press Ctrl+E)"
echo "  3. Navigate to Audio Effects → Equalizer tab"
echo "  4. Check the 'Enable' checkbox at the top"
echo "  5. Adjust bass frequency sliders:"
echo "     - 60 Hz slider: Move to +10 dB (boost bass)"
echo "     - 170 Hz slider: Move to +8 dB (boost bass)"
echo "     - 310 Hz slider: Move to +4 dB (boost upper bass)"
echo "  6. Adjust mid-range sliders to reduce interference:"
echo "     - 600 Hz slider: Move to -4 dB (reduce mids)"
echo "     - 1 kHz slider: Move to -5 dB (reduce mids)"
echo "     - 3 kHz slider: Move to -4 dB (reduce mids)"
echo "  7. Close the dialog (settings save automatically)"
echo ""
echo "Goal: Create an EQ curve that isolates bass frequencies for easier hearing"