#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Verify Audio Spectrum Task ==="

kill_vlc ga
sleep 1

# Ensure Music directory exists
mkdir -p /home/ga/Music
chown ga:ga /home/ga/Music

# Generate test audio file with frequency cutoff at 16kHz
# This simulates an upsampled MP3 masquerading as hi-fi FLAC
echo "Generating test audio file..."

# Generate 30-second audio with sine waves at various frequencies
# Use a sweep from 100Hz to 48kHz to show full spectrum
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=30" \
    -f lavfi -i "sine=frequency=880:duration=30" \
    -f lavfi -i "sine=frequency=1760:duration=30" \
    -filter_complex "[0:a][1:a][2:a]amix=inputs=3:duration=longest" \
    -ar 96000 -c:a pcm_s24le \
    /tmp/full_spectrum_temp.wav 2>/dev/null || {
    echo "ERROR: Failed to generate base audio"
    exit 1
}

# Apply low-pass filter at 16kHz to simulate MP3 upsampling artifact
ffmpeg -y -i /tmp/full_spectrum_temp.wav \
    -af "lowpass=f=16000" \
    -ar 96000 -c:a flac \
    /home/ga/Music/questionable_hifi.flac 2>/dev/null || {
    echo "ERROR: Failed to process audio file"
    exit 1
}

# Cleanup temp file
rm -f /tmp/full_spectrum_temp.wav

# Verify file was created
if [ ! -f /home/ga/Music/questionable_hifi.flac ]; then
    echo "ERROR: Audio file was not created"
    exit 1
fi

echo "✅ Audio file created: $(ls -lh /home/ga/Music/questionable_hifi.flac)"

# Set ownership
chown ga:ga /home/ga/Music/questionable_hifi.flac

# Reset VLC configuration to defaults (remove any existing visualizer settings)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    sed -i '/^audio-visual=/d' "$VLC_RC"
    sed -i '/^effect-list=/d' "$VLC_RC"
    sed -i '/^visual=/d' "$VLC_RC"
    echo "VLC visualizer settings cleared"
fi

# Clear VLC recent files list
if [ -f /home/ga/.local/share/vlc/ml.xspf ]; then
    rm -f /home/ga/.local/share/vlc/ml.xspf
fi

# Launch VLC
echo "Launching VLC..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show > /tmp/vlc_spectrum_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_spectrum_task.log
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

echo "=== Verify Audio Spectrum Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Enable spectrum analyzer:"
echo "     Method A: Tools → Effects and Filters (Ctrl+E) → Audio Effects → Visualization"
echo "     Method B: Tools → Preferences → Audio → Enable visualization"
echo "  2. Set visualization to 'Spectrum' or 'Spectrometer'"
echo "  3. Open the audio file: /home/ga/Music/questionable_hifi.flac"
echo "     Use: Media → Open File (Ctrl+O)"
echo "  4. Play the file to observe the spectrum"
echo ""
echo "Real-world context: You're checking if this 'lossless' audio file"
echo "is genuine or an upsampled MP3. Look for frequency cutoff patterns."