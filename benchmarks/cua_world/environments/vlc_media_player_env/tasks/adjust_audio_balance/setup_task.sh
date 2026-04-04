#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adjust Audio Balance Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Reset VLC audio balance to default (0.0 = center)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing audio balance settings
    sed -i '/^audio-stereo-balance=/d' "$VLC_RC"
    sed -i '/^audio-channel-mixer-balance=/d' "$VLC_RC"
    sed -i '/^spatializer-balance=/d' "$VLC_RC"
    sed -i '/^stereo-widen-balance=/d' "$VLC_RC"
    sed -i '/^headphone-effect=/d' "$VLC_RC"
    sed -i '/^audio-filter=/d' "$VLC_RC"
    echo "Audio balance reset to default (center)"
fi

# Generate stereo test audio file (30 seconds, 440 Hz sine wave)
TEST_AUDIO="/home/ga/Music/balance_test.mp3"

if [ ! -f "$TEST_AUDIO" ]; then
    echo "Generating stereo test audio..."
    su - ga -c "ffmpeg -f lavfi -i 'sine=frequency=440:duration=30' -ac 2 -ar 44100 '$TEST_AUDIO' -y > /tmp/ffmpeg_audio_gen.log 2>&1" || {
        echo "ERROR: Failed to generate test audio"
        cat /tmp/ffmpeg_audio_gen.log
        exit 1
    }
    echo "✅ Test audio generated: $TEST_AUDIO"
else
    echo "Test audio already exists: $TEST_AUDIO"
fi

# Verify audio file exists and is valid
if [ ! -f "$TEST_AUDIO" ] || [ ! -s "$TEST_AUDIO" ]; then
    echo "ERROR: Test audio file is missing or empty"
    exit 1
fi

# Check if VLC is already running and kill it
if pgrep -f "vlc" > /dev/null; then
    echo "VLC is already running, killing it..."
    pkill -f "vlc"
    sleep 1
fi

# Launch VLC with RC interface enabled and test audio
echo "Launching VLC with RC interface and test audio..."
su - ga -c "DISPLAY=:1 vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TEST_AUDIO' > /tmp/vlc_balance_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_balance_task.log || true
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_balance_task.log || true
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..10}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "RC interface ready"
        break
    fi
    echo "RC interface not ready, waiting... ($i/10)"
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
    echo "VLC window focused (WID: $wid)"
else
    echo "⚠️ Could not get VLC window ID, but continuing..."
fi

# Wait for VLC to fully initialize
sleep 2

echo "=== Adjust Audio Balance Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════════"
echo "  SCENARIO: Your RIGHT earphone is BROKEN! 🎧💔"
echo "  You need to shift all audio to the LEFT channel."
echo ""
echo "  GOAL: Adjust audio balance to strongly favor LEFT channel"
echo "  TARGET: Balance value between -0.7 and -1.0"
echo "  (where -1.0 = full left, 0.0 = center, +1.0 = full right)"
echo ""
echo "  STEPS:"
echo "  1. Open: Tools → Effects and Filters (or press Ctrl+E)"
echo "  2. Go to: Audio Effects tab"
echo "  3. Find: Spatializer or Advanced section"
echo "  4. Locate: Balance or Stereo slider"
echo "  5. Drag slider STRONGLY to the LEFT"
echo "  6. Ensure: Effect is ENABLED (checkbox checked)"
echo "  7. Close dialog to apply"
echo "  8. Save settings: Tools → Preferences → Save"
echo ""
echo "  Alternative locations:"
echo "  - Audio Effects → Advanced → Stereo mode"
echo "  - Tools → Preferences → Audio → Output modules"
echo "════════════════════════════════════════════════════════════════"