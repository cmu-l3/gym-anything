#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prepare Mono Broadcast Task ==="

kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Music/submissions
mkdir -p /home/ga/Music/broadcast_ready
chown -R ga:ga /home/ga/Music/submissions
chown -R ga:ga /home/ga/Music/broadcast_ready

# Generate a stereo test audio file (acoustic guitar simulation)
# Using ffmpeg to create a 30-second stereo audio with different content in each channel
# This simulates a listener submission that needs to be converted to mono
echo "Generating stereo test audio file..."
ffmpeg -f lavfi -i "sine=frequency=440:duration=30" -f lavfi -i "sine=frequency=554:duration=30" \
    -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" \
    -map "[a]" -ar 44100 -ac 2 -sample_fmt s16 \
    /home/ga/Music/submissions/listener_recording.wav -y 2>/tmp/setup_mono_audio.log

# Verify the test file was created correctly
if [ ! -f /home/ga/Music/submissions/listener_recording.wav ]; then
    echo "ERROR: Failed to create test audio file"
    cat /tmp/setup_mono_audio.log
    exit 1
fi

# Check that it's actually stereo
CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 /home/ga/Music/submissions/listener_recording.wav 2>/dev/null)
if [ "$CHANNELS" != "2" ]; then
    echo "ERROR: Test file is not stereo (found $CHANNELS channels)"
    exit 1
fi

echo "✅ Stereo audio file created successfully (2 channels)"

# Set proper ownership
chown -R ga:ga /home/ga/Music/submissions
chown -R ga:ga /home/ga/Music/broadcast_ready

# Launch VLC (empty, so agent can use Convert/Save dialog)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_mono_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_mono_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Prepare Mono Broadcast Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Convert /home/ga/Music/submissions/listener_recording.wav to mono"
echo "  2. Use Media -> Convert/Save (Ctrl+R)"
echo "  3. Add source file: /home/ga/Music/submissions/listener_recording.wav"
echo "  4. Click Convert/Save button"
echo "  5. Choose audio profile and set channels to mono"
echo "  6. Set destination: /home/ga/Music/broadcast_ready/listener_recording_mono.wav"
echo "  7. Start conversion"
echo ""
echo "📁 Input: /home/ga/Music/submissions/listener_recording.wav (stereo, 2 channels)"
echo "🎯 Output: /home/ga/Music/broadcast_ready/listener_recording_mono.wav (mono, 1 channel)"