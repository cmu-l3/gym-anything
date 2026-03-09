#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compensate Audio Imbalance Task ==="

# Kill any existing VLC instances
kill_vlc ga

sleep 1

# Ensure required directories exist
mkdir -p /home/ga/Music
mkdir -p /home/ga/.config/vlc

# Generate stereo audio test file if it doesn't exist
AUDIO_FILE="/home/ga/Music/audiobook_sample.mp3"

if [ ! -f "$AUDIO_FILE" ]; then
    echo "Generating stereo audio test file..."
    # Create a 30-second stereo audio file with clear left/right channel separation
    # This uses sine waves at different frequencies for each channel
    ffmpeg -f lavfi -i "sine=frequency=440:duration=30:sample_rate=48000" \
           -f lavfi -i "sine=frequency=523:duration=30:sample_rate=48000" \
           -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" \
           -map "[a]" -codec:a libmp3lame -q:a 2 -y "$AUDIO_FILE" > /tmp/audio_gen.log 2>&1
    
    if [ ! -f "$AUDIO_FILE" ]; then
        echo "ERROR: Failed to create audio file"
        cat /tmp/audio_gen.log
        exit 1
    fi
    
    chown ga:ga "$AUDIO_FILE"
    chmod 644 "$AUDIO_FILE"
    echo "✅ Audio file created: $AUDIO_FILE"
else
    echo "✅ Audio file already exists: $AUDIO_FILE"
fi

# Reset VLC audio balance to default (centered) - this is the initial state
VLC_RC="/home/ga/.config/vlc/vlcrc"

echo "Resetting VLC audio balance to default (centered)..."

if [ -f "$VLC_RC" ]; then
    # Remove any existing audio-balance setting
    sed -i '/^audio-balance=/d' "$VLC_RC"
fi

# Ensure vlcrc exists and add default balance
if [ ! -f "$VLC_RC" ]; then
    mkdir -p "$(dirname "$VLC_RC")"
    cat > "$VLC_RC" <<EOF
# VLC media player configuration
[core]
EOF
fi

# Add default balance setting (0.0 = centered)
echo "audio-balance=0.000000" >> "$VLC_RC"

chown -R ga:ga /home/ga/.config/vlc
chmod 644 "$VLC_RC"

echo "Initial audio balance: 0.0 (centered/default)"

# Launch VLC with RC interface enabled and the audio file
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$AUDIO_FILE' > /tmp/vlc_balance_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_balance_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    cat /tmp/vlc_balance_task.log
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
    echo "VLC window focused (wid: $wid)"
else
    echo "⚠️ Could not get VLC window ID"
fi

# Additional delay to ensure VLC is fully initialized
sleep 2

echo "=== Compensate Audio Imbalance Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. VLC is now playing a stereo audio file at centered balance (0.0)"
echo "  2. You need to adjust the audio balance to compensate for a weak left earbud"
echo "  3. Shift the balance toward LEFT (negative value) between -0.3 and -0.8"
echo "  4. Methods to adjust balance:"
echo "     a) Tools → Effects and Filters (Ctrl+E) → Audio Effects → Stereo"
echo "     b) Audio menu → Audio Device / Stereo Mode"
echo "     c) Keyboard shortcuts: Shift+Left to shift left"
echo "  5. Target: Balance between -0.3 and -0.8 (60-80% toward left)"
echo "  6. Test by listening to ensure audio sounds balanced with your 'defective' left earbud"
echo ""