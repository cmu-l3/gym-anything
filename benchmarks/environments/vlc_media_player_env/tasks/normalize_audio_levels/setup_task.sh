#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up VLC Audio Normalization Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Create necessary directories
echo "Creating directories..."
mkdir -p /home/ga/Videos/lectures
mkdir -p /home/ga/.config/vlc

# Generate two test videos with different audio levels
echo "Generating test videos with different audio levels..."

# Video 1: Very quiet audio (-18dB, simulating poorly mastered content)
# Using sine wave for consistent audio test
if [ ! -f /home/ga/Videos/lectures/lecture_quiet.mp4 ]; then
    echo "Generating lecture_quiet.mp4 with very quiet audio..."
    ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=30 \
           -f lavfi -i "sine=frequency=440:duration=30" \
           -filter_complex "[1:a]volume=-18dB[aquiet]" \
           -map 0:v -map "[aquiet]" \
           -c:v libx264 -preset ultrafast -crf 28 \
           -c:a aac -b:a 128k -ar 44100 \
           -y /home/ga/Videos/lectures/lecture_quiet.mp4 2>&1 | grep -v "deprecated"
    
    echo "✅ Generated lecture_quiet.mp4 (very quiet, -18dB)"
else
    echo "lecture_quiet.mp4 already exists"
fi

# Video 2: Normal audio level (0dB, typical for well-mastered content)
if [ ! -f /home/ga/Videos/lectures/lecture_normal.mp4 ]; then
    echo "Generating lecture_normal.mp4 with normal audio..."
    ffmpeg -f lavfi -i testsrc=duration=30:size=640x480:rate=30 \
           -f lavfi -i "sine=frequency=880:duration=30" \
           -filter_complex "[1:a]volume=0dB[anormal]" \
           -map 0:v -map "[anormal]" \
           -c:v libx264 -preset ultrafast -crf 28 \
           -c:a aac -b:a 128k -ar 44100 \
           -y /home/ga/Videos/lectures/lecture_normal.mp4 2>&1 | grep -v "deprecated"
    
    echo "✅ Generated lecture_normal.mp4 (normal level, 0dB)"
else
    echo "lecture_normal.mp4 already exists"
fi

# Verify files were created
if [[ ! -f /home/ga/Videos/lectures/lecture_quiet.mp4 ]]; then
    echo "ERROR: Failed to generate lecture_quiet.mp4"
    exit 1
fi

if [[ ! -f /home/ga/Videos/lectures/lecture_normal.mp4 ]]; then
    echo "ERROR: Failed to generate lecture_normal.mp4"
    exit 1
fi

echo "Test videos created successfully:"
ls -lh /home/ga/Videos/lectures/

# Reset VLC config to defaults (remove any existing audio filters)
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [[ -f "$VLC_RC" ]]; then
    echo "Resetting VLC audio configuration..."
    
    # Backup existing config
    cp "$VLC_RC" "${VLC_RC}.backup_$(date +%s)" 2>/dev/null || true
    
    # Remove audio filter settings to ensure clean state
    sed -i '/^audio-filter=/d' "$VLC_RC"
    sed -i '/^norm-max-level=/d' "$VLC_RC"
    sed -i '/^normvol/d' "$VLC_RC"
    sed -i '/^compressor/d' "$VLC_RC"
    sed -i '/^audio-time-stretch=/d' "$VLC_RC"
    
    echo "Audio filter settings cleared from vlcrc"
else
    echo "No existing vlcrc found, will be created on first run"
fi

# Set correct ownership
chown -R ga:ga /home/ga/Videos/lectures
chown -R ga:ga /home/ga/.config/vlc 2>/dev/null || true

# Launch VLC with the first (quiet) video to demonstrate the problem
echo "Launching VLC with quiet lecture video..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --extraintf rc --rc-host localhost:9999 /home/ga/Videos/lectures/lecture_quiet.mp4 > /tmp/vlc_audio_norm_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_norm_task.log 2>/dev/null || true
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

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 400 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    echo "VLC window focused (WID: $wid)"
fi

# Wait a moment for everything to settle
sleep 2

echo ""
echo "=== Audio Normalization Task Setup Complete ==="
echo ""
echo "📝 TASK: Configure VLC audio normalization for consistent volume"
echo ""
echo "PROBLEM: Two videos have very different audio levels:"
echo "  - lecture_quiet.mp4: Very quiet (-18dB) - needs volume at ~180%"
echo "  - lecture_normal.mp4: Normal (0dB) - comfortable at ~80%"
echo ""
echo "GOAL: Enable audio normalization/compression so both play at consistent volume"
echo ""
echo "SUGGESTED APPROACHES:"
echo "  1. Tools → Effects and Filters (Ctrl+E) → Audio Effects → Enable Compressor"
echo "  2. Tools → Preferences (Ctrl+P) → Show All → Audio → Filters → Volume normalizer"
echo "  3. Any method that enables audio normalization/compression in VLC config"
echo ""
echo "VERIFICATION: Settings must persist to ~/.config/vlc/vlcrc"
echo ""