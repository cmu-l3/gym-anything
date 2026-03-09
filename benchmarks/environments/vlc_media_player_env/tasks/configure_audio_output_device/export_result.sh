#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Audio Output Device Result ==="

# Query VLC RC interface for current audio output settings
AUDIO_OUTPUT=""
AUDIO_DEVICE=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio settings..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract audio output info from RC status
        # RC interface may show audio output module in status
        AUDIO_OUTPUT=$(echo "$RC_OUTPUT" | grep -oP 'audio output:\s*\K[^\s]+' || echo "")
        
        if [ -n "$AUDIO_OUTPUT" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio output from VLC RC: $AUDIO_OUTPUT"
        else
            echo "⚠️ Could not extract audio output from RC interface"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC to ensure configuration is saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to save configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Copy VLC configuration file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config file found: $VLC_RC"
    cp "$VLC_RC" /tmp/vlc_audio_config.txt
    
    # Extract audio-related settings for logging
    echo "Audio-related settings in vlcrc:"
    grep -E "^(aout|alsa-audio-device|pulse-sink|audio-output)=" "$VLC_RC" || echo "  (No audio settings found)"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Create a JSON result with audio configuration info
AOUT_VALUE=$(grep "^aout=" /tmp/vlc_audio_config.txt 2>/dev/null | cut -d= -f2 || echo "")
ALSA_DEVICE=$(grep "^alsa-audio-device=" /tmp/vlc_audio_config.txt 2>/dev/null | cut -d= -f2 || echo "")
PULSE_SINK=$(grep "^pulse-sink=" /tmp/vlc_audio_config.txt 2>/dev/null | cut -d= -f2 || echo "")

cat > /tmp/vlc_audio_device_result.json <<EOF
{
    "aout": "$AOUT_VALUE",
    "alsa_device": "$ALSA_DEVICE",
    "pulse_sink": "$PULSE_SINK",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Audio device result saved to /tmp/vlc_audio_device_result.json"
cat /tmp/vlc_audio_device_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_audio_device_completed.txt
echo "Audio device configuration task completed" >> /tmp/vlc_audio_device_completed.txt

echo "=== Export Complete ==="