#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adjust Pitch Without Tempo Result ==="

# Paths
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLC_QT_CONFIG="/home/ga/.config/vlc/vlc-qt-interface.conf"

# Query VLC RC interface for current audio filter state (if possible)
RUNTIME_FILTERS=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio filters..."

    # Query audio filters from RC interface
    RC_OUTPUT=$(echo "afilter" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Extract filter names from RC output
        RUNTIME_FILTERS=$(echo "$RC_OUTPUT" | grep -oP '(?:afilter|>)\s*\K[^\s]+' | head -1 || echo "")

        if [ -n "$RUNTIME_FILTERS" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio filters from VLC RC: $RUNTIME_FILTERS"
        else
            echo "⚠️ No audio filters found in RC output"
        fi
    else
        echo "⚠️ Could not query RC interface for audio filters"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "Closing VLC..."
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    } || {
        echo "⚠️ Failed to close VLC gracefully; force killing"
        kill_vlc ga
        sleep 1
    }
fi

# Read VLC configuration files
echo "Reading VLC configuration files..."

PITCH_CONFIG="{}"

if [ -f "$VLC_RC" ]; then
    # Extract pitch-related settings from vlcrc
    AUDIO_FILTER=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2- | head -1 || echo "")
    PITCH_SHIFT=$(grep "^pitch-shift=" "$VLC_RC" | cut -d= -f2- | head -1 || echo "")
    SCALETEMPO_PITCH=$(grep "^scaletempo-pitch=" "$VLC_RC" | cut -d= -f2- | head -1 || echo "")
    PITCH_SEMITONES=$(grep "^pitch-semitones=" "$VLC_RC" | cut -d= -f2- | head -1 || echo "")
    PLAYBACK_RATE=$(grep "^rate=" "$VLC_RC" | cut -d= -f2- | head -1 || echo "1.0")
    PLAYBACK_SPEED=$(grep "^speed=" "$VLC_RC" | cut -d= -f2- | head -1 || echo "")
    
    # Build JSON for pitch config
    PITCH_JSON=""
    
    if [ -n "$AUDIO_FILTER" ]; then
        PITCH_JSON="\"audio-filter\": \"${AUDIO_FILTER}\""
    fi
    
    if [ -n "$PITCH_SHIFT" ]; then
        [ -n "$PITCH_JSON" ] && PITCH_JSON="${PITCH_JSON},"
        PITCH_JSON="${PITCH_JSON}\"pitch-shift\": \"${PITCH_SHIFT}\""
    fi
    
    if [ -n "$SCALETEMPO_PITCH" ]; then
        [ -n "$PITCH_JSON" ] && PITCH_JSON="${PITCH_JSON},"
        PITCH_JSON="${PITCH_JSON}\"scaletempo-pitch\": \"${SCALETEMPO_PITCH}\""
    fi
    
    if [ -n "$PITCH_SEMITONES" ]; then
        [ -n "$PITCH_JSON" ] && PITCH_JSON="${PITCH_JSON},"
        PITCH_JSON="${PITCH_JSON}\"pitch-semitones\": \"${PITCH_SEMITONES}\""
    fi
    
    if [ -n "$PLAYBACK_RATE" ]; then
        [ -n "$PITCH_JSON" ] && PITCH_JSON="${PITCH_JSON},"
        PITCH_JSON="${PITCH_JSON}\"rate\": \"${PLAYBACK_RATE}\""
    fi
    
    if [ -n "$PLAYBACK_SPEED" ]; then
        [ -n "$PITCH_JSON" ] && PITCH_JSON="${PITCH_JSON},"
        PITCH_JSON="${PITCH_JSON}\"speed\": \"${PLAYBACK_SPEED}\""
    fi
    
    if [ -n "$PITCH_JSON" ]; then
        PITCH_CONFIG="{${PITCH_JSON}}"
        echo "Found pitch configuration in vlcrc"
    else
        echo "⚠️ No pitch configuration found in vlcrc"
    fi
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Also check Qt interface config for effects dialog state
QT_CONFIG_DATA=""
if [ -f "$VLC_QT_CONFIG" ]; then
    # Look for audio effects settings
    if grep -q "equalizer\|pitch\|audio-filter" "$VLC_QT_CONFIG" 2>/dev/null; then
        QT_CONFIG_DATA="found"
        echo "Qt interface config has audio effects settings"
    fi
fi

# Copy vlcrc for detailed verification
cp "$VLC_RC" /tmp/vlc_pitch_vlcrc.txt 2>/dev/null || echo "" > /tmp/vlc_pitch_vlcrc.txt

# Write JSON result file
cat > /tmp/vlc_pitch_result.json <<EOF
{
    "pitch_config": $PITCH_CONFIG,
    "runtime_filters": "$RUNTIME_FILTERS",
    "runtime_captured": $RUNTIME_CAPTURED,
    "qt_config_found": "$([ -n "$QT_CONFIG_DATA" ] && echo "true" || echo "false")",
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Pitch adjustment result saved to /tmp/vlc_pitch_result.json"
cat /tmp/vlc_pitch_result.json

echo "$(date)" > /tmp/vlc_pitch_completed.txt
echo "Pitch adjustment task export completed" >> /tmp/vlc_pitch_completed.txt

echo "=== Export Complete ==="