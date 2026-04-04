#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Surround Channels Task ==="

kill_vlc ga
sleep 1

# Create audio test directory
mkdir -p /home/ga/Music/audio_tests
chown -R ga:ga /home/ga/Music/audio_tests

# Generate 5.1 channel test file using ffmpeg
# Creates a simple 5.1 WAV file with tones on each channel
echo "Generating 5.1 surround test audio file..."
if [ ! -f /home/ga/Music/audio_tests/surround_test_5.1.wav ]; then
    # Generate 6 channels (FL, FR, Center, LFE, SL, SR) with distinct frequencies
    ffmpeg -f lavfi -i "sine=frequency=440:duration=6" \
           -f lavfi -i "sine=frequency=554:duration=6" \
           -f lavfi -i "sine=frequency=659:duration=6" \
           -f lavfi -i "sine=frequency=220:duration=6" \
           -f lavfi -i "sine=frequency=880:duration=6" \
           -f lavfi -i "sine=frequency=1046:duration=6" \
           -filter_complex "[0:a][1:a][2:a][3:a][4:a][5:a]join=inputs=6:channel_layout=5.1[a]" \
           -map "[a]" -t 36 /home/ga/Music/audio_tests/surround_test_5.1.wav -y \
           > /tmp/ffmpeg_surround_gen.log 2>&1 || {
        echo "⚠️ Failed to generate 5.1 file, creating fallback stereo file"
        ffmpeg -f lavfi -i "sine=frequency=440:duration=36" \
               -ac 2 /home/ga/Music/audio_tests/surround_test_5.1.wav -y \
               > /tmp/ffmpeg_fallback.log 2>&1
    }
    chown ga:ga /home/ga/Music/audio_tests/surround_test_5.1.wav
fi

# Generate stereo reference file
echo "Generating stereo reference audio file..."
if [ ! -f /home/ga/Music/audio_tests/stereo_reference.wav ]; then
    ffmpeg -f lavfi -i "sine=frequency=440:duration=6" \
           -f lavfi -i "sine=frequency=880:duration=6" \
           -filter_complex "[0:a][1:a]amerge=inputs=2[a]" \
           -map "[a]" -ac 2 -t 12 /home/ga/Music/audio_tests/stereo_reference.wav -y \
           > /tmp/ffmpeg_stereo_gen.log 2>&1
    chown ga:ga /home/ga/Music/audio_tests/stereo_reference.wav
fi

# Setup VLC config with INCORRECT initial settings
# This simulates the "problem state" that agent needs to fix
VLC_RC="/home/ga/.config/vlc/vlcrc"
mkdir -p /home/ga/.config/vlc
chown ga:ga /home/ga/.config/vlc

echo "Setting initial VLC audio configuration (incorrect state)..."
cat > "$VLC_RC" << 'EOF'
# VLC media player configuration
[core]
# Audio output
aout=pulse

# Audio device (stereo/built-in - WRONG for surround)
audio-device=alsa_output.pci-0000_00_1b.0.analog-stereo

# Downmix to stereo (ENABLED - WRONG for surround)
audio-downmix-to-stereo=1

# Other settings
volume-save=1
audio-volume=256
EOF

chown ga:ga "$VLC_RC"
chmod 644 "$VLC_RC"

echo "Initial vlcrc content:"
cat "$VLC_RC"

# Launch VLC with the test audio file
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show /home/ga/Music/audio_tests/surround_test_5.1.wav > /tmp/vlc_surround_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_surround_task.log
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

# Pause playback to make UI interactions easier
sleep 1
su - ga -c "DISPLAY=:1 xdotool key space" || true

echo "=== Verify Surround Channels Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is currently using STEREO output with DOWNMIXING enabled"
echo "  2. Open Preferences: Tools → Preferences (Ctrl+P)"
echo "  3. Go to Audio section/tab"
echo "  4. Change 'Output module' or 'Device' to a multi-channel device:"
echo "     - Look for: HDMI, USB, DisplayPort, Surround, 5.1"
echo "     - Avoid: Built-in, Analog Stereo, Default (stereo)"
echo "  5. Disable 'Downmix to stereo' checkbox (if visible)"
echo "  6. Click 'Save' to apply changes"
echo "  7. VLC may need to be restarted for changes to take effect"
echo ""
echo "Current (wrong) config:"
echo "  - Device: alsa_output.pci-0000_00_1b.0.analog-stereo (STEREO)"
echo "  - Downmix: ENABLED (converts 5.1 → 2.0)"