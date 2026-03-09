#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Audio Output Device Task ==="

# Kill any existing VLC instances
kill_vlc ga
sleep 1

# Reset VLC audio configuration to defaults
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_CONFIG_DIR="/home/ga/.config/vlc"

# Ensure config directory exists
mkdir -p "$VLC_CONFIG_DIR"
chown ga:ga "$VLC_CONFIG_DIR"

if [ -f "$VLC_RC" ]; then
    # Remove any existing audio output settings to reset to defaults
    sed -i '/^aout=/d' "$VLC_RC"
    sed -i '/^alsa-audio-device=/d' "$VLC_RC"
    sed -i '/^pulse-sink=/d' "$VLC_RC"
    sed -i '/^audio-output=/d' "$VLC_RC"
    echo "Audio output settings reset to defaults"
else
    # Create minimal config file
    touch "$VLC_RC"
    chown ga:ga "$VLC_RC"
    echo "Created new VLC config file"
fi

# Create a dummy ALSA configuration to simulate multiple audio devices
# This makes the environment more realistic for the agent
ALSA_CONF="/home/ga/.asoundrc"
cat > "$ALSA_CONF" <<'EOF'
# Simulated ALSA audio devices for VLC task
pcm.!default {
    type plug
    slave.pcm "hw:0,0"
}

pcm.hdmi {
    type plug
    slave.pcm "hw:0,3"
    hint {
        description "HDMI Audio Output"
    }
}

pcm.analog {
    type plug
    slave.pcm "hw:0,0"
    hint {
        description "Analog Audio Output"
    }
}
EOF
chown ga:ga "$ALSA_CONF"
echo "Created ALSA configuration with multiple devices"

# Set up PulseAudio dummy sinks (if PulseAudio is available)
if command -v pactl >/dev/null 2>&1; then
    echo "Setting up PulseAudio dummy sinks..."
    # Run as ga user to create user-level sinks
    su - ga -c "DISPLAY=:1 pactl load-module module-null-sink sink_name=hdmi_output sink_properties=device.description='HDMI_Audio_Output' 2>/dev/null || true" || true
    su - ga -c "DISPLAY=:1 pactl load-module module-null-sink sink_name=analog_output sink_properties=device.description='Analog_Audio_Output' 2>/dev/null || true" || true
    echo "PulseAudio sinks created"
fi

# Launch VLC with RC interface enabled and a looping video
echo "Launching VLC with RC interface..."
su - ga -c "DISPLAY=:1 LIBVA_DRIVER_NAME='' VDPAU_DRIVER='' vlc --avcodec-hw=none --no-video-title-show --loop --extraintf rc --rc-host localhost:9999 /home/ga/Videos/sample_video.mp4 > /tmp/vlc_audio_device_task.log 2>&1 &"

if ! wait_for_process "vlc" 15; then
    echo "ERROR: VLC failed to start"
    cat /tmp/vlc_audio_device_task.log || true
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

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus VLC window
wid=$(get_vlc_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# Wait for VLC to fully render
sleep 2

echo "=== Configure Audio Output Device Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open VLC Preferences: Tools → Preferences (or Ctrl+P)"
echo "  2. Click 'All' button at bottom-left to show all settings"
echo "  3. Navigate to: Audio → Output modules"
echo "  4. Change 'Audio output module' from 'Automatic' to 'ALSA' or 'PulseAudio'"
echo "  5. Configure device:"
echo "     - For ALSA: Set 'ALSA audio device' to HDMI device"
echo "     - For PulseAudio: Set 'PulseAudio server' or device to HDMI output"
echo "  6. Click 'Save' button at bottom"
echo "  7. Settings will persist in ~/.config/vlc/vlcrc"
echo ""
echo "Available simulated devices:"
echo "  - ALSA: hdmi, analog"
echo "  - PulseAudio: hdmi_output, analog_output"