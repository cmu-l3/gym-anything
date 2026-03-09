#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Enhance Recording Clarity Task ==="

kill_vlc ga
sleep 1

TASK_DIR="/workspace/tasks/enhance_recording_clarity"
USER_HOME="/home/ga"
MUSIC_DIR="$USER_HOME/Music"
TEMP_DIR="/tmp/audio_enhance_setup_$$"

# Create directories
mkdir -p "$MUSIC_DIR"
mkdir -p "$TEMP_DIR"

# Check if espeak-ng is installed, if not install it
if ! command -v espeak-ng &> /dev/null; then
    echo "Installing espeak-ng for speech generation..."
    apt-get update -qq
    apt-get install -y -qq espeak-ng > /dev/null 2>&1
fi

# Generate noisy audio recording with speech
echo "Generating noisy audio recording..."

# First, generate clean speech using espeak-ng
espeak-ng -v en-us -s 140 -w "$TEMP_DIR/clean_speech.wav" \
  "Attention. The factory on Oak Street is dumping chemicals into the river at night. Check the east drainage pipe between midnight and two AM. This has been happening for three weeks." 2>/dev/null || true

# If espeak-ng failed, create a simple tone-based placeholder
if [ ! -f "$TEMP_DIR/clean_speech.wav" ]; then
    echo "Espeak-ng failed, generating placeholder audio..."
    ffmpeg -f lavfi -i "sine=frequency=440:duration=20" -ar 22050 -y "$TEMP_DIR/clean_speech.wav" 2>/dev/null
fi

# Add background noise layers
# 1. Generate wind noise (low-frequency rumble)
ffmpeg -f lavfi -i "anoisesrc=d=20:c=brown:r=44100:a=0.4" -y "$TEMP_DIR/wind.wav" 2>/dev/null

# 2. Generate traffic noise burst (car passing at 8-12 seconds)
ffmpeg -f lavfi -i "anoisesrc=d=4:c=white:r=44100:a=0.6" -y "$TEMP_DIR/traffic_burst.wav" 2>/dev/null

# 3. Add ambient background noise
ffmpeg -f lavfi -i "anoisesrc=d=20:c=pink:r=44100:a=0.3" -y "$TEMP_DIR/ambient.wav" 2>/dev/null

# Mix clean speech with noise layers
ffmpeg -i "$TEMP_DIR/clean_speech.wav" \
  -i "$TEMP_DIR/wind.wav" \
  -i "$TEMP_DIR/ambient.wav" \
  -filter_complex \
  "[0:a]volume=0.5[speech]; \
   [1:a]volume=1.2[wind]; \
   [2:a]volume=0.8[ambient]; \
   [speech][wind]amix=inputs=2:duration=longest[mix1]; \
   [mix1][ambient]amix=inputs=2:duration=longest[mix2]; \
   [mix2]volume=0.9,highpass=f=50,lowpass=f=8000[out]" \
  -map "[out]" -y "$TEMP_DIR/noisy_base.wav" 2>/dev/null

# Add traffic burst at specific time (8 seconds)
ffmpeg -i "$TEMP_DIR/noisy_base.wav" \
  -i "$TEMP_DIR/traffic_burst.wav" \
  -filter_complex \
  "[1:a]adelay=8000|8000[delayed]; \
   [0:a][delayed]amix=inputs=2:duration=first:weights=1 0.7[out]" \
  -map "[out]" -y "$TEMP_DIR/noisy_recording.wav" 2>/dev/null

# Convert to MP3 with low quality to simulate phone recording
ffmpeg -i "$TEMP_DIR/noisy_recording.wav" \
  -codec:a libmp3lame -b:a 96k -ar 22050 \
  -y "$MUSIC_DIR/noisy_recording.mp3" 2>/dev/null

# Set ownership
chown -R ga:ga "$MUSIC_DIR"
chmod 644 "$MUSIC_DIR/noisy_recording.mp3"

# Clean up temp files
rm -rf "$TEMP_DIR"

echo "Noisy recording created: $MUSIC_DIR/noisy_recording.mp3"

# Store original audio info for verification
ffprobe -v error -show_entries format=duration,bit_rate,size \
  -show_entries stream=codec_name,sample_rate,channels \
  "$MUSIC_DIR/noisy_recording.mp3" > /tmp/original_audio_info.txt 2>&1 || true

# Launch VLC without file (agent will open it)
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_enhance_task.log 2>&1 &"

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

echo "=== Enhance Recording Clarity Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open the noisy recording: /home/ga/Music/noisy_recording.mp3"
echo "  2. Go to Tools -> Effects and Filters (Ctrl+E)"
echo "  3. In Audio Effects tab, enable and configure:"
echo "     - Compressor: Set ratio to 4:1 or higher"
echo "     - Equalizer: Reduce low frequencies (60Hz, 170Hz), boost midrange (600Hz-3kHz)"
echo "  4. Listen to verify improvement"
echo "  5. Convert/Save to: /home/ga/Music/enhanced_recording.mp3"
echo "     Use Media -> Convert/Save (Ctrl+R)"
echo "     Ensure audio effects are applied during conversion"