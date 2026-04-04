#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Practice Music Transcription Task ==="

kill_vlc ga
sleep 1

# Generate jazz-style audio file if it doesn't exist
AUDIO_FILE="/home/ga/Music/confirmation_solo.mp3"
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Generating jazz solo audio file..."
    # Create a 45-second audio with jazz-like chord progression (complex enough to need transcription)
    # Using multiple sine waves at jazz-relevant frequencies
    ffmpeg -f lavfi -i "sine=frequency=440:duration=45" \
           -f lavfi -i "sine=frequency=554.37:duration=45" \
           -f lavfi -i "sine=frequency=659.25:duration=45" \
           -f lavfi -i "sine=frequency=880:duration=45" \
           -filter_complex "[0:a][1:a][2:a][3:a]amix=inputs=4:duration=longest:dropout_transition=2,volume=0.25" \
           -b:a 192k "$AUDIO_FILE" 2>/dev/null || {
        echo "ERROR: Failed to generate audio file"
        exit 1
    }
    chown ga:ga "$AUDIO_FILE"
    echo "✅ Audio file generated: $AUDIO_FILE"
fi

# Reset VLC config to defaults (speed=1.0, no time-stretching)
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc/
chown ga:ga /home/ga/.config/vlc/

# Create minimal vlcrc with default settings
cat > "$VLC_RC" <<EOF
# VLC configuration for Practice Music Transcription task
[core]
audio-time-stretch=0
rate=1.000000

# Remove any existing audio filters
[audio-filter]
audio-filter=

# Ensure no speed modifications
[playback]
input-fast-seek=0
EOF

chown ga:ga "$VLC_RC"
echo "✅ VLC config reset to defaults (speed=1.0x, no time-stretch)"

# Launch VLC with RC interface enabled and audio file
echo "Launching VLC with audio file..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_transcription_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_transcription_task.log
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
    echo "✅ VLC window focused"
fi

# Give agent clear view of VLC interface
sleep 2

echo "=== Practice Music Transcription Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a jazz solo audio file at normal speed (1.0x)"
echo "  2. Enable time-stretching to preserve pitch:"
echo "     - Open Tools → Effects and Filters (Ctrl+E)"
echo "     - Go to Audio Effects tab"
echo "     - Click 'Advanced' or 'Spatializer' sub-tab"
echo "     - Enable 'Time stretching' checkbox"
echo "     - Close dialog"
echo "  3. Reduce playback speed to 0.60x (60%):"
echo "     - Press '[' key multiple times (each press reduces speed)"
echo "     - OR use Playback → Speed → Slower (fine)"
echo "     - OR Playback → Speed → Custom → enter 0.60"
echo "  4. Target: 0.60x speed with pitch preservation enabled"