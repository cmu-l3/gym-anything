#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Audio Desync Result ==="

# Initialize result variables
AUDIO_DESYNC_VALUE=""
CONFIG_SOURCE="none"

# Method 1: Read from VLC config file (most reliable)
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading audio-desync from vlcrc..."
    
    # Extract audio-desync value
    if grep -q "^audio-desync=" "$VLC_RC"; then
        AUDIO_DESYNC_VALUE=$(grep "^audio-desync=" "$VLC_RC" | tail -1 | cut -d= -f2)
        CONFIG_SOURCE="vlcrc"
        echo "✅ Found audio-desync in vlcrc: ${AUDIO_DESYNC_VALUE}ms"
    else
        echo "⚠️ audio-desync setting not found in vlcrc"
        AUDIO_DESYNC_VALUE="0"
    fi
    
    # Copy vlcrc for verification
    cp "$VLC_RC" /tmp/vlc_desync_vlcrc.txt
else
    echo "⚠️ VLC config file not found: $VLC_RC"
    AUDIO_DESYNC_VALUE="0"
fi

# Method 2: Also check Qt interface config as backup
QT_CONFIG="/home/ga/.config/vlc/vlc-qt-interface.conf"

if [ -f "$QT_CONFIG" ]; then
    if grep -q "audio-desync" "$QT_CONFIG"; then
        QT_DESYNC=$(grep "audio-desync" "$QT_CONFIG" | tail -1 | cut -d= -f2)
        echo "Qt config also shows: ${QT_DESYNC}ms"
        
        # Use Qt value if vlcrc didn't have it
        if [ "$CONFIG_SOURCE" = "none" ] && [ -n "$QT_DESYNC" ]; then
            AUDIO_DESYNC_VALUE="$QT_DESYNC"
            CONFIG_SOURCE="qt-config"
        fi
    fi
    
    cp "$QT_CONFIG" /tmp/vlc_desync_qtconfig.txt 2>/dev/null || true
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Ensure VLC is fully closed before final config read
sleep 1

# Re-read vlcrc one more time after VLC closes (settings may be written on exit)
if [ -f "$VLC_RC" ]; then
    if grep -q "^audio-desync=" "$VLC_RC"; then
        AUDIO_DESYNC_VALUE=$(grep "^audio-desync=" "$VLC_RC" | tail -1 | cut -d= -f2)
        CONFIG_SOURCE="vlcrc-final"
        echo "✅ Final audio-desync value: ${AUDIO_DESYNC_VALUE}ms"
    fi
    
    # Copy final vlcrc
    cp "$VLC_RC" /tmp/vlc_desync_vlcrc_final.txt
fi

# Validate the value is numeric
if ! [[ "$AUDIO_DESYNC_VALUE" =~ ^-?[0-9]+$ ]]; then
    echo "⚠️ Invalid audio-desync value: '$AUDIO_DESYNC_VALUE', defaulting to 0"
    AUDIO_DESYNC_VALUE="0"
fi

# Write JSON result file for verifier
cat > /tmp/vlc_desync_result.json <<EOF
{
    "audio_desync_ms": $AUDIO_DESYNC_VALUE,
    "config_source": "$CONFIG_SOURCE",
    "target_delay_ms": ${TARGET_DELAY_MS:-250},
    "tolerance_ms": ${TOLERANCE_MS:-50}
}
EOF

echo "✅ Audio desync result saved to /tmp/vlc_desync_result.json"
cat /tmp/vlc_desync_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_desync_completed.txt
echo "Audio desync: ${AUDIO_DESYNC_VALUE}ms" >> /tmp/vlc_desync_completed.txt
echo "Config source: ${CONFIG_SOURCE}" >> /tmp/vlc_desync_completed.txt

echo "=== Export Complete ==="
echo "Final audio-desync setting: ${AUDIO_DESYNC_VALUE}ms"