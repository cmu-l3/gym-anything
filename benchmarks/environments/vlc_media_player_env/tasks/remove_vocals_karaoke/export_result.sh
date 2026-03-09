#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Remove Vocals for Karaoke Result ==="

# Give VLC a moment if effects dialog is still open
sleep 1

# Close VLC gracefully to ensure config is written to disk
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    echo "Closing VLC to flush config..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Copy VLC config file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config found: $VLC_RC"
    cp "$VLC_RC" /tmp/vlc_karaoke_vlcrc.txt
    
    # Extract audio filter settings
    echo "Extracting audio filter settings..."
    
    AUDIO_FILTER=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2 || echo "")
    SPATIALIZER_MIX=$(grep "^spatializer-mix=" "$VLC_RC" | cut -d= -f2 || echo "")
    WIDENER_MIX=$(grep "^stereo-widener-mix=" "$VLC_RC" | cut -d= -f2 || echo "")
    EQUALIZER_BANDS=$(grep "^equalizer-bands=" "$VLC_RC" | cut -d= -f2 || echo "")
    EQUALIZER_PREAMP=$(grep "^equalizer-preamp=" "$VLC_RC" | cut -d= -f2 || echo "")
    
    # Create JSON result
    cat > /tmp/vlc_karaoke_result.json <<EOF
{
    "audio_filter": "$AUDIO_FILTER",
    "spatializer_mix": "$SPATIALIZER_MIX",
    "stereo_widener_mix": "$WIDENER_MIX",
    "equalizer_bands": "$EQUALIZER_BANDS",
    "equalizer_preamp": "$EQUALIZER_PREAMP",
    "config_found": true,
    "timestamp": "$(date -Iseconds)"
}
EOF
    
    echo "✅ Audio filter settings extracted"
    cat /tmp/vlc_karaoke_result.json
    
else
    echo "⚠️ VLC config not found at $VLC_RC"
    
    # Create empty result
    cat > /tmp/vlc_karaoke_result.json <<EOF
{
    "audio_filter": "",
    "config_found": false,
    "error": "vlcrc not found",
    "timestamp": "$(date -Iseconds)"
}
EOF
fi

echo "$(date)" > /tmp/vlc_karaoke_completed.txt
echo "Remove vocals for karaoke task export completed" >> /tmp/vlc_karaoke_completed.txt

echo "=== Export Complete ==="