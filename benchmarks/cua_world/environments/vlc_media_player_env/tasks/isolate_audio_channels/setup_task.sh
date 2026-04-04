#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Isolate Audio Channels Task ==="

kill_vlc ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Music
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Music
chown ga:ga /home/ga/Documents

# Generate a 5.1 surround sound test file
# We'll create a file with distinct tones in each channel
AUDIO_FILE="/home/ga/Music/surround_test_5.1.wav"

echo "Generating 5.1 surround test audio file..."

# Create a 10-second test file with distinct frequencies per channel
# FL=440Hz, FR=554Hz, FC=659Hz, RL=330Hz, RR=277Hz, LFE=110Hz
# This approach creates 6 mono files and then merges them into 5.1

# Generate individual channel files
ffmpeg -f lavfi -i "sine=frequency=440:duration=10" -y /tmp/fl.wav 2>/dev/null || true
ffmpeg -f lavfi -i "sine=frequency=554:duration=10" -y /tmp/fr.wav 2>/dev/null || true
ffmpeg -f lavfi -i "sine=frequency=659:duration=10" -y /tmp/fc.wav 2>/dev/null || true
ffmpeg -f lavfi -i "sine=frequency=330:duration=10" -y /tmp/rl.wav 2>/dev/null || true
ffmpeg -f lavfi -i "sine=frequency=277:duration=10" -y /tmp/rr.wav 2>/dev/null || true
ffmpeg -f lavfi -i "sine=frequency=110:duration=10" -y /tmp/lfe.wav 2>/dev/null || true

# Merge into 5.1 layout
ffmpeg -i /tmp/fl.wav -i /tmp/fr.wav -i /tmp/fc.wav -i /tmp/rl.wav -i /tmp/rr.wav -i /tmp/lfe.wav \
    -filter_complex "[0:a][1:a][2:a][3:a][4:a][5:a]amerge=inputs=6,pan=5.1|FL=c0|FR=c1|FC=c2|BL=c3|BR=c4|LFE=c5" \
    -ac 6 -ar 48000 -y "$AUDIO_FILE" 2>/dev/null || {
    
    # Fallback: create a simpler stereo file that can be used for testing
    echo "Creating fallback stereo test file..."
    ffmpeg -f lavfi -i "sine=frequency=440:duration=10" \
           -f lavfi -i "sine=frequency=880:duration=10" \
           -filter_complex "[0:a][1:a]amerge=inputs=2[a]" \
           -map "[a]" -ac 2 -ar 48000 -y "$AUDIO_FILE" 2>/dev/null || true
}

# Clean up temp files
rm -f /tmp/fl.wav /tmp/fr.wav /tmp/fc.wav /tmp/rl.wav /tmp/rr.wav /tmp/lfe.wav

# Verify file was created
if [ ! -f "$AUDIO_FILE" ]; then
    echo "ERROR: Failed to create test audio file"
    exit 1
fi

echo "✅ Audio test file created: $AUDIO_FILE"
ls -lh "$AUDIO_FILE"

# Probe audio info
echo "Audio file info:"
ffprobe -v error -show_entries stream=channels,channel_layout,codec_name,sample_rate -of default=noprint_wrappers=1 \
    "$AUDIO_FILE" 2>/dev/null || echo "Could not probe audio file"

# Reset VLC config to ensure no audio effects are active
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing audio filter settings
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^stereo-mode=/d' "$VLC_RC"
    sed -i '/^headphone-dim=/d' "$VLC_RC"
    sed -i '/^remap=/d' "$VLC_RC"
    sed -i '/^channelmixer=/d' "$VLC_RC"
    echo "Audio filters reset"
fi

# Set volume to reasonable level
if [ -f "$VLC_RC" ]; then
    sed -i 's/audio-volume=.*/audio-volume=192/' "$VLC_RC" 2>/dev/null || true
fi

# Launch VLC with RC interface enabled
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_channel_task.log 2>&1 &"

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

# Pause playback initially so agent can configure before testing
echo "Pausing playback..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 1

chown ga:ga "$AUDIO_FILE"

echo "=== Isolate Audio Channels Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is playing a 5.1 surround test audio file (paused)"
echo "  2. Each channel has a distinct frequency tone"
echo "  3. Configure VLC to isolate ONLY the front-right channel"
echo "  4. Methods to try:"
echo "     - Tools → Effects and Filters (Ctrl+E) → Audio Effects"
echo "     - Audio → Stereo Mode → select 'Right' or similar"
echo "     - Audio → Audio Device settings"
echo "  5. Create a log at /home/ga/Documents/channel_test_results.txt"
echo "     documenting your configuration"
echo "  6. The goal is to mute all channels except front-right"