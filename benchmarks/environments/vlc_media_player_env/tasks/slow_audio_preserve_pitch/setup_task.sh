#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Slow Audio Preserve Pitch Task ==="

kill_vlc ga
sleep 1

# Ensure videos directory exists
mkdir -p /home/ga/Videos

# Generate a test video with tonal audio (simulating guitar tutorial)
# 30 second video with musical tones at different frequencies
VIDEO_FILE="/home/ga/Videos/guitar_solo_tutorial.mp4"

if [ ! -f "$VIDEO_FILE" ]; then
    echo "Generating guitar tutorial video with tonal audio..."
    
    # Create a video with color bars and a sequence of musical tones
    # Using frequencies that correspond to musical notes (A4=440Hz, D5=587Hz, E5=659Hz, etc.)
    ffmpeg -f lavfi -i "color=c=blue:s=1280x720:d=30:r=30" \
           -f lavfi -i "sine=frequency=440:duration=6,sine=frequency=494:duration=6,sine=frequency=523:duration=6,sine=frequency=587:duration=6,sine=frequency=659:duration=6,concat=n=5:v=0:a=1" \
           -c:v libx264 -preset ultrafast -c:a aac -b:a 192k -shortest \
           "$VIDEO_FILE" -y 2>/dev/null || {
        echo "Fallback: Creating simpler tutorial video..."
        ffmpeg -f lavfi -i "color=c=blue:s=1280x720:d=30:r=30" \
               -f lavfi -i "sine=frequency=440:duration=30" \
               -c:v libx264 -preset ultrafast -c:a aac -b:a 192k \
               "$VIDEO_FILE" -y
    }
    
    chown ga:ga "$VIDEO_FILE"
    echo "✓ Tutorial video created"
else
    echo "✓ Tutorial video already exists"
fi

# Reset VLC config to defaults (ensure clean state with normal playback speed)
VLC_RC="/home/ga/.config/vlc/vlcrc"
su - ga -c "rm -rf /home/ga/.config/vlc"
su - ga -c "mkdir -p /home/ga/.config/vlc"

# Create minimal VLC config with default settings
cat > "$VLC_RC" << 'EOF'
[qt]
qt-privacy-ask=0

[core]
rate=1.0

[audio]
audio-time-stretch=1
EOF

chown ga:ga "$VLC_RC"
echo "✓ VLC config reset to defaults (rate=1.0)"

# Launch VLC with RC interface enabled
echo "Launching VLC with guitar tutorial..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$VIDEO_FILE' > /tmp/vlc_slow_audio_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_slow_audio_task.log
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
        echo "✓ RC interface ready"
        break
    fi
    echo "  Attempt $i/10..."
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
    echo "✓ VLC window focused"
fi

# Give video a moment to start playing
sleep 2

echo "=== Slow Audio Preserve Pitch Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  GOAL: Configure VLC to play at 0.65x speed with pitch preservation"
echo ""
echo "  Method 1 (Recommended - Precise):"
echo "    1. Open Playback menu → Speed"
echo "    2. Select 'Faster (fine)' or 'Slower (fine)' or 'Custom'"
echo "    3. If Custom, enter 0.65 as the rate"
echo ""
echo "  Method 2 (Alternative - Incremental):"
echo "    1. Press '[' key multiple times to slow down"
echo "    2. Monitor the speed indicator in VLC"
echo "    3. Stop when reaching approximately 0.65x"
echo ""
echo "  Method 3 (Settings):"
echo "    1. Open Tools → Preferences"
echo "    2. Show settings: All"
echo "    3. Navigate to Input / Codecs → Playback speed"
echo ""
echo "  Pitch preservation (time-stretching) should be enabled by default."
echo "  Verify in Tools → Preferences → Audio → 'Enable time stretching audio'"
echo ""
echo "  Target speed: 0.65x (65% of normal speed)"
echo "  Video file: $VIDEO_FILE"