#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Transpose Audio Pitch Result ==="

# Initialize result variables
AUDIO_FILTER=""
PITCH_SHIFT=""
PLAYBACK_RATE=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio settings..."

    # Query status from RC interface
    RC_STATUS=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_STATUS" ]; then
        echo "RC Status captured, parsing for audio effects..."
        
        # Try to extract pitch or audio filter info
        # Note: RC interface may not expose all audio effect settings
        AUDIO_INFO=$(echo "$RC_STATUS" | grep -i "audio\|pitch\|filter" || echo "")
        
        if [ -n "$AUDIO_INFO" ]; then
            echo "Audio info from RC: $AUDIO_INFO"
        fi
    fi

    # Query playback rate
    RATE_OUTPUT=$(echo "get_rate" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$RATE_OUTPUT" ]; then
        PLAYBACK_RATE=$(echo "$RATE_OUTPUT" | grep -oP '\d+' | head -1)
        echo "Playback rate from RC: $PLAYBACK_RATE"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Wait for VLC to fully close and save config
sleep 1

# Primary verification: Read VLC config file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration from vlcrc..."

    # Check for audio filter setting
    if grep -q "^audio-filter=" "$VLC_RC"; then
        AUDIO_FILTER=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2- | head -1)
        echo "Audio filter found: $AUDIO_FILTER"
    fi

    # Check for pitch shift setting (various possible keys)
    for key in "pitch-shift" "audio-pitch-shift" "scaletempo-stride" "pitch" "audiorate-shift"; do
        if grep -q "^${key}=" "$VLC_RC"; then
            PITCH_SHIFT=$(grep "^${key}=" "$VLC_RC" | cut -d= -f2 | head -1)
            echo "Pitch setting found (${key}): $PITCH_SHIFT"
            break
        fi
    done

    # If no explicit pitch-shift, check for scaletempo or other audio effects
    if [ -z "$PITCH_SHIFT" ]; then
        # Check if any pitch-related module is configured
        for key in "scaletempo-tempo" "audio-tempo"; do
            if grep -q "^${key}=" "$VLC_RC"; then
                TEMPO_VAL=$(grep "^${key}=" "$VLC_RC" | cut -d= -f2 | head -1)
                echo "Tempo/scaletempo setting found (${key}): $TEMPO_VAL"
            fi
        done
    fi
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Determine if audio filter is enabled
AUDIO_FILTER_ENABLED="false"
if [ -n "$AUDIO_FILTER" ]; then
    # Check if filter contains pitch-related modules
    if echo "$AUDIO_FILTER" | grep -qE "scaletempo|pitch|audiorate"; then
        AUDIO_FILTER_ENABLED="true"
        RUNTIME_CAPTURED="true"
    fi
fi

# Create JSON result
cat > /tmp/vlc_pitch_result.json <<EOF
{
    "audio_filter": "$AUDIO_FILTER",
    "audio_filter_enabled": $AUDIO_FILTER_ENABLED,
    "pitch_shift": "$PITCH_SHIFT",
    "playback_rate": "$PLAYBACK_RATE",
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "vlcrc"
}
EOF

echo "✅ Pitch result saved to /tmp/vlc_pitch_result.json"
cat /tmp/vlc_pitch_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_pitch_completed.txt
echo "Transpose audio pitch task completed" >> /tmp/vlc_pitch_completed.txt

echo "=== Export Complete ==="