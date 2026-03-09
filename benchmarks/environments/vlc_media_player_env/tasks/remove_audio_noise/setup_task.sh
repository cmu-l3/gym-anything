#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Remove Audio Noise Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure directories exist
mkdir -p /home/ga/Music
mkdir -p /home/ga/.config/vlc
mkdir -p /home/ga/Pictures/vlc

# Generate noisy audio file with 60Hz hum and background noise
echo "Generating noisy audio file with 60Hz hum and tape hiss..."

# Create a 3-minute audio file with:
# - Speech-like frequency content (250Hz, 500Hz, 1000Hz, 2000Hz)
# - 60Hz electrical hum and 120Hz harmonic
# - White noise (tape hiss)
ffmpeg -f lavfi -i "sine=frequency=250:duration=180" \
    -f lavfi -i "sine=frequency=500:duration=180" \
    -f lavfi -i "sine=frequency=1000:duration=180" \
    -f lavfi -i "sine=frequency=2000:duration=180" \
    -f lavfi -i "sine=frequency=60:duration=180" \
    -f lavfi -i "sine=frequency=120:duration=180" \
    -f lavfi -i "anoisesrc=duration=180:color=white:amplitude=0.08" \
    -filter_complex "\
        [0]volume=0.12,asetrate=44100*1.01,aresample=44100[v1];\
        [1]volume=0.09,asetrate=44100*0.99,aresample=44100[v2];\
        [2]volume=0.07,asetrate=44100*1.02,aresample=44100[v3];\
        [3]volume=0.05,asetrate=44100*0.98,aresample=44100[v4];\
        [4]volume=0.30[hum60];\
        [5]volume=0.18[hum120];\
        [6]volume=1.0[hiss];\
        [v1][v2][v3][v4][hum60][hum120][hiss]amix=inputs=7:duration=longest:normalize=0[out]" \
    -map "[out]" -ar 44100 -ac 2 -b:a 192k \
    /home/ga/Music/historical_meeting.mp3 -y 2>&1 | head -20

if [ ! -f /home/ga/Music/historical_meeting.mp3 ]; then
    echo "ERROR: Failed to generate noisy audio file"
    exit 1
fi

echo "✅ Noisy audio file created at /home/ga/Music/historical_meeting.mp3"
ls -lh /home/ga/Music/historical_meeting.mp3

# Set ownership
chown -R ga:ga /home/ga/Music
chmod 644 /home/ga/Music/historical_meeting.mp3

# Store the original audio characteristics for verification
ffprobe -v error -show_entries format=duration,bit_rate,size \
    -show_entries stream=codec_name,sample_rate,channels \
    -of json /home/ga/Music/historical_meeting.mp3 \
    > /tmp/original_audio_info.json 2>&1

echo "Original audio info saved"

# Remove any existing cleaned output
rm -f /home/ga/Music/cleaned_meeting.mp3

# Launch VLC with the noisy audio (without auto-playing to let agent control it)
echo "Launching VLC with noisy audio file..."
su - ga -c "DISPLAY=:1 vlc --no-video-title-show /home/ga/Music/historical_meeting.mp3 > /tmp/vlc_noise_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_noise_task.log || true
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

# Pause playback so agent can work on filters first
sleep 1
echo "Pausing playback..."
su - ga -c "DISPLAY=:1 xdotool key space" || true
sleep 0.5

echo "=== Remove Audio Noise Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is playing the noisy audio file: /home/ga/Music/historical_meeting.mp3"
echo "  2. The audio has severe 60Hz electrical hum and tape hiss"
echo "  3. Apply audio filters to clean it:"
echo "     - Open Tools -> Effects and Filters (Ctrl+E)"
echo "     - Go to Audio Effects tab"
echo "     - Enable Equalizer and create notches at 60Hz, 120Hz, 180Hz"
echo "     - Enable Compressor to even out volume"
echo "  4. Save the filtered audio:"
echo "     - Method 1: Use Media -> Convert/Save (Ctrl+R)"
echo "     - Method 2: Click Record button while playing"
echo "  5. Save output as: /home/ga/Music/cleaned_meeting.mp3"
echo ""
echo "Target: Reduce background noise while preserving speech clarity"