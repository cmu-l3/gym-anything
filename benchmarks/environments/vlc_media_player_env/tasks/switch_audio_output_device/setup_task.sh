#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Switch Audio Output Device Task ==="

kill_vlc ga
sleep 1

# Ensure task directory exists
TASK_DIR="/home/ga/vlc_audio_output_task"
mkdir -p "$TASK_DIR"
chown -R ga:ga "$TASK_DIR"

# Set up PulseAudio virtual sinks to simulate multiple output devices
echo "Setting up PulseAudio virtual sinks..."

# Remove any existing test sinks first
pactl unload-module module-null-sink 2>/dev/null || true
sleep 0.5

# Create virtual audio devices
pactl load-module module-null-sink sink_name=studio_monitors sink_properties=device.description="Studio_Monitors"
pactl load-module module-null-sink sink_name=reference_headphones sink_properties=device.description="Reference_Headphones"
pactl load-module module-null-sink sink_name=desktop_speakers sink_properties=device.description="Desktop_Speakers"

sleep 1

# List available sinks for reference
pactl list short sinks > "$TASK_DIR/available_sinks.txt"
echo "Available PulseAudio sinks:"
cat "$TASK_DIR/available_sinks.txt"

# Generate test audio file if it doesn't exist (looping sine wave for continuous playback)
TEST_AUDIO="/home/ga/Music/test_audio_loop.mp3"
if [ ! -f "$TEST_AUDIO" ]; then
    echo "Generating test audio file..."
    ffmpeg -f lavfi -i "sine=frequency=440:duration=10" \
        -af "volume=0.3" \
        -c:a libmp3lame -b:a 128k \
        /home/ga/Music/test_audio_single.mp3 -y 2>/dev/null
    
    # Create looping version (60 seconds total)
    ffmpeg -stream_loop 5 -i /home/ga/Music/test_audio_single.mp3 \
        -c copy "$TEST_AUDIO" -y 2>/dev/null
    
    chown ga:ga "$TEST_AUDIO"
    echo "✅ Test audio created: $TEST_AUDIO"
fi

# Set VLC to use PulseAudio and default to studio_monitors sink
VLC_CONFIG_DIR="/home/ga/.config/vlc"
mkdir -p "$VLC_CONFIG_DIR"

# Configure VLC to use PulseAudio (ensure clean state)
cat > "$VLC_CONFIG_DIR/vlcrc" << 'EOF'
[core]
aout=pulse

[pulse]
audio-device=

EOF

chown -R ga:ga "$VLC_CONFIG_DIR"

# Set PulseAudio default sink to studio_monitors (initial state)
pactl set-default-sink studio_monitors

# Launch VLC with RC interface enabled and test audio in loop mode
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 '$TEST_AUDIO' > /tmp/vlc_audio_output_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_output_task.log
    exit 1
fi

if ! wait_for_window "VLC media player" 20; then
    echo "ERROR: VLC window did not appear"
    exit 1
fi

# Wait for RC interface to be ready
echo "Waiting for RC interface..."
for i in {1..15}; do
    if echo "info" | nc -w 1 localhost 9999 > /dev/null 2>&1; then
        echo "✅ RC interface ready"
        break
    fi
    if [ $i -eq 15 ]; then
        echo "⚠️ RC interface did not become ready, continuing anyway"
    fi
    sleep 1
done

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    sleep 0.5
fi

# Wait a moment for audio to start playing
sleep 2

# Verify VLC is actually playing audio through PulseAudio
echo "Checking initial audio routing..."
INITIAL_ROUTING=$(pactl list sink-inputs | grep -A 20 "application.name = \"vlc\"" | grep "Sink:" | head -1 || echo "")
echo "Initial routing: $INITIAL_ROUTING"

# Save VLC PID and start time for verification
VLC_PID=$(pgrep -f "vlc.*$TEST_AUDIO" | head -1)
echo "$VLC_PID" > "$TASK_DIR/vlc_pid.txt"
echo "$(date +%s)" > "$TASK_DIR/task_start_time.txt"

# Create instruction file
cat > "$TASK_DIR/instructions.txt" << 'EOF'
Audio Output Device Switching Task
====================================

Scenario: You are an audio engineer checking a mix on different speaker systems.
You have VLC playing test audio through Studio_Monitors, but you need to switch 
to Reference_Headphones to check the high-frequency response.

Your task:
1. VLC is currently playing audio through "Studio_Monitors"
2. Switch VLC's audio output device to "Reference_Headphones"
3. Do this WITHOUT stopping or restarting VLC
4. Audio should continue playing seamlessly during the switch

Methods to accomplish this:
  Method A (Recommended): 
    - Open Audio menu → Audio Device
    - Select "Reference_Headphones"
  
  Method B (Advanced):
    - Tools → Preferences (Ctrl+P)
    - Show settings: All (bottom-left button)
    - Navigate to: Audio → Output modules → PulseAudio
    - Set audio device to "Reference_Headphones"
    - Click Save
    - Audio should switch without restart

Available devices:
- Studio_Monitors (current default)
- Reference_Headphones (target - SWITCH TO THIS)
- Desktop_Speakers

Success criteria:
- VLC audio stream routed to Reference_Headphones
- VLC continues playing (no restart)
- Setting persists in VLC configuration

Current PulseAudio sinks available:
EOF

pactl list short sinks >> "$TASK_DIR/instructions.txt"

chown -R ga:ga "$TASK_DIR"
cat "$TASK_DIR/instructions.txt"

echo ""
echo "=== Switch Audio Output Device Task Setup Complete ==="
echo "📝 VLC is playing test audio through Studio_Monitors"
echo "📝 Agent must switch output to Reference_Headphones"
echo "📝 Instructions available at: $TASK_DIR/instructions.txt"