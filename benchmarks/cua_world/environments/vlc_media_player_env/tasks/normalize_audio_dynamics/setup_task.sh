#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Normalize Audio Dynamics Task ==="

kill_vlc ga
sleep 1

# Create directories
mkdir -p /home/ga/Videos
mkdir -p /home/ga/.config/vlc

# Generate test video with exaggerated dynamic range
# This simulates the real-world problem: quiet dialogue, loud sound effects
echo "Generating test video with high dynamic range audio..."

cat > /tmp/generate_dynamic_video.sh << 'VIDEOSCRIPT'
#!/bin/bash
set -e

# Generate quiet audio section (simulating soft dialogue at -30dB)
ffmpeg -f lavfi -i "sine=frequency=300:duration=5" \
    -af "volume=-30dB" -ar 44100 -ac 2 -y /tmp/quiet_section.wav 2>/dev/null

# Generate loud audio section (simulating loud applause/effects at -5dB)
ffmpeg -f lavfi -i "anoisesrc=d=5:c=white:r=44100:a=0.5" \
    -af "volume=-5dB,highpass=f=200,lowpass=f=3000" -ar 44100 -ac 2 -y /tmp/loud_section.wav 2>/dev/null

# Concatenate: quiet -> loud -> quiet
echo "file '/tmp/quiet_section.wav'" > /tmp/audio_concat.txt
echo "file '/tmp/loud_section.wav'" >> /tmp/audio_concat.txt
echo "file '/tmp/quiet_section.wav'" >> /tmp/audio_concat.txt

ffmpeg -f concat -safe 0 -i /tmp/audio_concat.txt -c copy -y /tmp/dynamic_audio.wav 2>/dev/null

# Create video with this high-dynamic-range audio
# Use a simple color gradient video
ffmpeg -f lavfi -i "color=c=blue:s=640x480:d=15" -i /tmp/dynamic_audio.wav \
    -c:v libx264 -preset ultrafast -c:a aac -b:a 128k -shortest \
    -y /home/ga/Videos/school_play.mp4 2>/dev/null

# Cleanup temp files
rm -f /tmp/quiet_section.wav /tmp/loud_section.wav /tmp/dynamic_audio.wav /tmp/audio_concat.txt

echo "Video generated: /home/ga/Videos/school_play.mp4"
VIDEOSCRIPT

chmod +x /tmp/generate_dynamic_video.sh
/tmp/generate_dynamic_video.sh

if [ ! -f /home/ga/Videos/school_play.mp4 ]; then
    echo "ERROR: Failed to generate test video"
    exit 1
fi

# Reset VLC config to ensure compressor is disabled initially
VLC_RC="/home/ga/.config/vlc/vlcrc"

# Create clean config with compressor explicitly disabled
cat > "$VLC_RC" << 'VLCRC'
[core]
audio-filter=
metadata-network-access=0

[compressor]
audio-compressor-attack=1.400000
audio-compressor-ratio=6.000000
audio-compressor-knee=2.500000
audio-compressor-makeup-gain=0.000000
audio-compressor-release=100.000000
audio-compressor-rms-peak=0.000000
audio-compressor-threshold=-11.000000

[qt]
qt-privacy-ask=0
qt-start-minimized=0
VLCRC

# Set ownership
chown -R ga:ga /home/ga/Videos
chown -R ga:ga /home/ga/.config/vlc

echo "VLC config initialized with compressor DISABLED"

# Launch VLC with the high dynamic range video
echo "Launching VLC with test video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop /home/ga/Videos/school_play.mp4 > /tmp/vlc_normalize_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_normalize_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Click on center of screen to select current desktop (required for all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

echo "=== Normalize Audio Dynamics Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. The video has inconsistent audio: quiet parts (dialogue) and loud parts (effects)"
echo "  2. Enable audio compression to 'even out' the volume:"
echo "     a. Open: Tools → Effects and Filters (or press Ctrl+E)"
echo "     b. Go to: Audio Effects tab"
echo "     c. Select: Compressor sub-tab"
echo "     d. Check: Enable checkbox"
echo "     e. (Optional) Adjust parameters or use defaults"
echo "     f. Close dialog"
echo "  3. Play the video briefly to test the effect"
echo "  4. The compression will make quiet sounds louder and loud sounds softer"
echo ""
echo "Video location: /home/ga/Videos/school_play.mp4"
echo "Current status: Compressor DISABLED"