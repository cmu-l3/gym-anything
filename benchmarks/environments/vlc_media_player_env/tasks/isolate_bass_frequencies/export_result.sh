#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Isolate Bass Frequencies Result ==="

# Query VLC RC interface for equalizer settings if available
EQ_ENABLED="false"
EQ_BANDS=""
EQ_PREAMP=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Attempting to query VLC RC interface for equalizer settings..."
    
    # RC interface may not expose equalizer settings directly
    # We'll primarily rely on config file, but attempt to check status
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        # Check if any audio filter mentions are present
        if echo "$RC_OUTPUT" | grep -qi "equalizer\|audio.*filter"; then
            EQ_ENABLED="true"
            RUNTIME_CAPTURED="true"
            echo "✅ Equalizer appears to be active in VLC"
        fi
    fi
fi

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to flush config..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Wait a moment for config file to be written
sleep 1

# Read VLC config file (primary verification method)
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading equalizer settings from VLC config..."
    
    # Check if equalizer is enabled (presence of equalizer-preamp indicates enabled)
    if grep -q "^equalizer-preamp=" "$VLC_RC"; then
        EQ_ENABLED="true"
        EQ_PREAMP=$(grep "^equalizer-preamp=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Equalizer enabled: preamp = $EQ_PREAMP"
    fi
    
    # Extract equalizer bands
    if grep -q "^equalizer-bands=" "$VLC_RC"; then
        EQ_BANDS=$(grep "^equalizer-bands=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Equalizer bands: $EQ_BANDS"
    fi
    
    # Copy entire config file for detailed verification
    cp "$VLC_RC" /tmp/vlc_eq_config.txt
    
else
    echo "⚠️ VLC config file not found at $VLC_RC"
fi

# Create JSON result file with all equalizer information
cat > /tmp/vlc_bass_eq_result.json <<EOF
{
    "eq_enabled": $EQ_ENABLED,
    "eq_preamp": "${EQ_PREAMP:-not_set}",
    "eq_bands": "${EQ_BANDS:-not_set}",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "source": "vlcrc"
}
EOF

echo "✅ Equalizer result saved to /tmp/vlc_bass_eq_result.json"
cat /tmp/vlc_bass_eq_result.json

echo "$(date)" > /tmp/vlc_bass_eq_completed.txt
echo "Bass frequency isolation task completed" >> /tmp/vlc_bass_eq_completed.txt

echo "=== Export Complete ==="