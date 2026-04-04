#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Adjust Playback Speed Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Reset VLC playback rate to default (1.0x = normal speed)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    # Remove any existing playback rate settings to ensure clean start
    sed -i '/^rate=/d' "$VLC_RC"
    sed -i '/^playback-speed=/d' "$VLC_RC"
    echo "Playback speed reset to default (1.0x)"
fi

# Ensure we have a test audio file (60 seconds)
AUDIO_FILE="/home/ga/Music/speed_test_audio.mp3"

if [ ! -f "$AUDIO_FILE" ]; then
    echo "Generating 60-second test audio file..."
    # Generate a simple audio file with sine wave and periodic beeps for timing reference
    ffmpeg -f lavfi -i "sine=frequency=440:duration=60" \
           -af "volume=0.3" \
           -y "$AUDIO_FILE" > /dev/null 2>&1 || {
        echo "Warning: Could not generate test audio, using existing sample"
        AUDIO_FILE="/home/ga/Music/sample_audio.mp3"
    }
    chown ga:ga "$AUDIO_FILE" 2>/dev/null || true
fi

# Check if vlc is already running and kill it
if pgrep -f "vlc" > /dev/null; then
    echo "VLC is already running, killing it..."
    pkill -f "vlc"
    sleep 1
fi

# Launch VLC with RC interface enabled for runtime querying
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_speed_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
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
    echo "RC interface not ready, waiting... ($i/10)"
    sleep 1
done

# Wait for VLC to fully render
sleep 3

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Click on VLC window to ensure it has focus and rendering is triggered
echo "Triggering window rendering..."
su - ga -c "DISPLAY=:1 xdotool mousemove 400 300 click 1" || true
sleep 1

# Verify initial playback rate via RC interface
echo "Verifying initial playback rate..."
INITIAL_RATE=$(echo "get_rate" | nc -w 2 localhost 9999 2>/dev/null | grep -oP '\d+\.?\d*' | head -1 || echo "1.0")
echo "Initial playback rate: ${INITIAL_RATE}x"

echo "=== Adjust Playback Speed Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VLC is now playing audio at normal speed (1.0x)"
echo "  2. Adjust playback speed to 1.5x using one of these methods:"
echo "     METHOD A (Keyboard - Recommended):"
echo "       - Press ']' key 5 times to increase speed from 1.0x to 1.5x"
echo "       - Each press increases by ~0.1x"
echo "     METHOD B (Menu):"
echo "       - Click Playback → Speed → Faster (multiple times)"
echo "       - Or Playback → Speed → Custom to set exact value"
echo "     METHOD C (Button):"
echo "       - Click speed indicator button in control bar (shows '1x')"
echo "       - Adjust slider or enter 1.5"
echo "  3. Verify status bar shows '1.5x' or '150%'"
echo "  4. Listen for faster audio playback (should sound sped up but clear)"