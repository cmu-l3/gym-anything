#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Surround Sound Test Task ==="

kill_vlc ga
sleep 1

# Create necessary directories
mkdir -p /home/ga/Music/test
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Music/test
chown ga:ga /home/ga/Documents
chown ga:ga /home/ga/Desktop

# Generate 5.1 surround sound test file with distinct tones per channel
echo "Generating 5.1 surround test audio file..."

# Create 5.1 test file using ffmpeg
# Each channel has a distinct frequency for identification
su - ga -c "ffmpeg -y \
    -f lavfi -i 'sine=frequency=440:duration=3' \
    -f lavfi -i 'sine=frequency=494:duration=3' \
    -f lavfi -i 'sine=frequency=523:duration=3' \
    -f lavfi -i 'sine=frequency=220:duration=3' \
    -f lavfi -i 'sine=frequency=587:duration=3' \
    -f lavfi -i 'sine=frequency=659:duration=3' \
    -filter_complex '[0:a][1:a][2:a][3:a][4:a][5:a]join=inputs=6:channel_layout=5.1[a]' \
    -map '[a]' -c:a pcm_s16le /home/ga/Music/test/surround_test_5.1.wav \
    > /tmp/ffmpeg_surround.log 2>&1" || {
    echo "ERROR: Failed to generate surround test file with 5.1"
    # Fallback: create simpler 6-channel file
    su - ga -c "ffmpeg -y \
        -f lavfi -i 'sine=frequency=440:duration=18' \
        -ac 6 -c:a pcm_s16le /home/ga/Music/test/surround_test_5.1.wav \
        > /tmp/ffmpeg_surround.log 2>&1"
}

if [ ! -f "/home/ga/Music/test/surround_test_5.1.wav" ]; then
    echo "ERROR: Failed to generate surround test file"
    cat /tmp/ffmpeg_surround.log
    exit 1
fi

echo "✅ Surround test file generated"
ls -lh /home/ga/Music/test/surround_test_5.1.wav

# Reset VLC audio settings to default (stereo)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove surround sound settings to create authentic challenge
    sed -i '/^aout=/d' "$VLC_RC"
    sed -i '/^audio-channels=/d' "$VLC_RC"
    sed -i '/^alsa-audio-device=/d' "$VLC_RC"
    sed -i '/^pulse-sink=/d' "$VLC_RC"
    sed -i '/surround/Id' "$VLC_RC"
    echo "Audio settings reset to default (stereo)"
fi

# Create instruction file on desktop
cat > /home/ga/Desktop/TASK_INSTRUCTIONS.txt <<'EOF'
SURROUND SOUND CONFIGURATION TASK
==================================

Goal: Configure VLC for 5.1 surround sound and test speaker setup

Steps:
1. VLC should launch automatically
2. Go to Tools → Preferences (Ctrl+P)
3. Click "All" button at bottom left to show all settings
4. Navigate to: Audio → Output modules
5. Set audio output module (e.g., "ALSA audio output" or "PulseAudio audio output")
6. Look for audio channels or surround sound settings
7. Set channels to 6 (for 5.1 configuration)
8. Click "Save" button
9. Restart VLC if needed (close and reopen)
10. Open test file: Media → Open File → /home/ga/Music/test/surround_test_5.1.wav
11. Play the file to test all channels
12. Create a report at: /home/ga/Documents/audio_config_report.txt

Report should include:
- Audio output module used (e.g., "ALSA" or "PulseAudio")
- Channel configuration (e.g., "5.1" or "6 channels")
- List of channels (FL, FR, C, LFE, RL, RR)
- Confirmation that test file was played
- Any observations about the configuration

Test File: /home/ga/Music/test/surround_test_5.1.wav
Report: /home/ga/Documents/audio_config_report.txt

Channel Information:
- FL (Front Left): 440 Hz
- FR (Front Right): 494 Hz  
- C (Center): 523 Hz
- LFE (Subwoofer): 220 Hz
- RL (Rear Left): 587 Hz
- RR (Rear Right): 659 Hz
EOF

chown ga:ga /home/ga/Desktop/TASK_INSTRUCTIONS.txt

# Launch VLC without any file (agent needs to configure first)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_surround_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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

echo "=== Surround Sound Test Task Setup Complete ==="
echo "📝 Task Instructions: /home/ga/Desktop/TASK_INSTRUCTIONS.txt"
echo "📝 Test File: /home/ga/Music/test/surround_test_5.1.wav"
echo "📝 Report Location: /home/ga/Documents/audio_config_report.txt"
echo ""
echo "Agent must:"
echo "  1. Configure VLC audio for 5.1 (6 channels)"
echo "  2. Play test file"
echo "  3. Create configuration report"