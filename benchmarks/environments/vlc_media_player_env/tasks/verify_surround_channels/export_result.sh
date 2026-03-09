#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Surround Channels Result ==="

# Give VLC a moment to flush any pending config writes
sleep 1

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Try graceful close
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "⚠️ VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
fi

# Copy VLC configuration file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found"
    cp "$VLC_RC" /tmp/vlc_audio_config.txt
    
    echo "Configuration summary:"
    echo "  Audio output module: $(grep '^aout=' "$VLC_RC" | cut -d= -f2 || echo 'not set')"
    echo "  Audio device: $(grep '^audio-device=' "$VLC_RC" | cut -d= -f2 || echo 'not set')"
    echo "  Downmix to stereo: $(grep '^audio-downmix-to-stereo=' "$VLC_RC" | cut -d= -f2 || echo 'not set')"
    
    # Extract key settings to JSON for easier parsing
    AOUT=$(grep '^aout=' "$VLC_RC" | cut -d= -f2 || echo "")
    DEVICE=$(grep '^audio-device=' "$VLC_RC" | cut -d= -f2 || echo "")
    DOWNMIX=$(grep '^audio-downmix-to-stereo=' "$VLC_RC" | cut -d= -f2 || echo "")
    
    cat > /tmp/vlc_audio_settings.json <<EOF
{
    "aout_module": "$AOUT",
    "audio_device": "$DEVICE",
    "downmix_to_stereo": "$DOWNMIX",
    "config_found": true
}
EOF
    
else
    echo "⚠️ VLC config file not found"
    cat > /tmp/vlc_audio_settings.json <<EOF
{
    "aout_module": "",
    "audio_device": "",
    "downmix_to_stereo": "",
    "config_found": false
}
EOF
fi

echo "✅ Audio settings exported to /tmp/vlc_audio_settings.json"
cat /tmp/vlc_audio_settings.json

# Create completion marker
echo "$(date)" > /tmp/vlc_surround_completed.txt
echo "Surround channels verification task completed" >> /tmp/vlc_surround_completed.txt

echo "=== Export Complete ==="