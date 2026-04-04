#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Normalize Audio Dynamics Result ==="

# Query VLC for runtime compressor status if still running
COMPRESSOR_STATUS="unknown"
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "VLC still running, attempting to query audio filter status..."
    
    # Try to check if compressor is active via process info or config
    # VLC doesn't expose this easily via RC interface, so we'll rely on config
    
    # Give VLC a moment to ensure settings are written
    sleep 1
fi

# Close VLC to ensure config is fully written to disk
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Copy VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config found, copying for verification..."
    cp "$VLC_RC" /tmp/vlc_normalize_vlcrc
    
    # Check config for compressor setting
    if grep -q "audio-filter.*compressor" "$VLC_RC"; then
        COMPRESSOR_STATUS="enabled"
        echo "✅ Compressor appears to be ENABLED in config"
    elif grep -q "^audio-filter=" "$VLC_RC"; then
        AUDIO_FILTER_VALUE=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2)
        if [ -z "$AUDIO_FILTER_VALUE" ]; then
            COMPRESSOR_STATUS="disabled"
            echo "⚠️ Compressor appears to be DISABLED (empty audio-filter)"
        else
            COMPRESSOR_STATUS="other_filter"
            echo "⚠️ Audio filter set to: $AUDIO_FILTER_VALUE"
        fi
    else
        COMPRESSOR_STATUS="not_set"
        echo "⚠️ No audio-filter setting found in config"
    fi
    
    # Also check for qt interface config which might have effects settings
    QT_CONF="/home/ga/.config/vlc/vlc-qt-interface.conf"
    if [ -f "$QT_CONF" ]; then
        cp "$QT_CONF" /tmp/vlc_normalize_qt_conf
        echo "✅ Copied Qt interface config"
    fi
else
    echo "❌ VLC config not found at: $VLC_RC"
fi

# Create result summary
cat > /tmp/vlc_normalize_result.json << EOF
{
    "compressor_status": "$COMPRESSOR_STATUS",
    "config_file_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Result summary saved to /tmp/vlc_normalize_result.json"
cat /tmp/vlc_normalize_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_normalize_completed.txt
echo "Normalize audio dynamics task completed" >> /tmp/vlc_normalize_completed.txt
echo "Compressor status: $COMPRESSOR_STATUS" >> /tmp/vlc_normalize_completed.txt

echo "=== Export Complete ==="