#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Audio Sync Result ==="

# Query VLC RC interface for audio delay settings
AUDIO_DELAY=""
AUDIO_DESYNC=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio delay..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract audio delay/desync from status output
        # VLC may report this as "audio delay: XXX" or similar
        AUDIO_DELAY=$(echo "$RC_OUTPUT" | grep -oP '(?:audio.?delay|audio.?desync):\s*\K[-+]?\d+' || echo "")

        if [ -n "$AUDIO_DELAY" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio delay from VLC RC: ${AUDIO_DELAY}ms"
        else
            echo "⚠️ Audio delay not found in RC status output"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi

    # Also try direct audiodelay command if available
    DELAY_OUTPUT=$(echo "audiodelay" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$DELAY_OUTPUT" ]; then
        DELAY_VAL=$(echo "$DELAY_OUTPUT" | grep -oP '[-+]?\d+' | head -1)
        if [ -n "$DELAY_VAL" ]; then
            AUDIO_DELAY="$DELAY_VAL"
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio delay from audiodelay command: ${AUDIO_DELAY}ms"
        fi
    fi
fi

# Close VLC to ensure config is written
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to save configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3  # Give time for config to be written
fi

# Read VLC config file (primary verification method)
VLC_RC="/home/ga/.config/vlc/vlcrc"
CONFIG_DELAY=""
CONFIG_FOUND="false"

if [ -f "$VLC_RC" ]; then
    echo "Reading audio delay from vlcrc..."

    # Check for various audio delay/desync keys
    if grep -q "^audio-desync=" "$VLC_RC"; then
        CONFIG_DELAY=$(grep "^audio-desync=" "$VLC_RC" | cut -d= -f2 | head -1)
        CONFIG_FOUND="true"
        echo "Found audio-desync: ${CONFIG_DELAY}"
    elif grep -q "^desync=" "$VLC_RC"; then
        CONFIG_DELAY=$(grep "^desync=" "$VLC_RC" | cut -d= -f2 | head -1)
        CONFIG_FOUND="true"
        echo "Found desync: ${CONFIG_DELAY}"
    elif grep -q "^audio-delay=" "$VLC_RC"; then
        CONFIG_DELAY=$(grep "^audio-delay=" "$VLC_RC" | cut -d= -f2 | head -1)
        CONFIG_FOUND="true"
        echo "Found audio-delay: ${CONFIG_DELAY}"
    fi

    if [ -z "$CONFIG_DELAY" ]; then
        echo "⚠️ No audio delay setting found in vlcrc"
        # Check if any audio-related settings were modified
        if grep -E "^(audio-desync|desync|audio-delay|audio-time-stretch)" "$VLC_RC" > /dev/null 2>&1; then
            echo "Found some audio timing settings in config"
            CONFIG_FOUND="true"
        fi
    fi
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Use config value as primary, runtime as fallback
FINAL_DELAY="${CONFIG_DELAY:-${AUDIO_DELAY:-0}}"

# Ensure it's a valid number
if ! [[ "$FINAL_DELAY" =~ ^[-+]?[0-9]+$ ]]; then
    echo "⚠️ Invalid delay value: $FINAL_DELAY, defaulting to 0"
    FINAL_DELAY="0"
fi

# Write JSON result file
cat > /tmp/vlc_audio_sync_result.json <<EOF
{
    "audio_delay_ms": $FINAL_DELAY,
    "config_found": $CONFIG_FOUND,
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "$([ "$CONFIG_FOUND" = "true" ] && echo "vlcrc" || echo "runtime")"
}
EOF

echo "✅ Audio sync result saved to /tmp/vlc_audio_sync_result.json"
cat /tmp/vlc_audio_sync_result.json

echo "$(date)" > /tmp/vlc_audio_sync_completed.txt
echo "Audio delay configured: ${FINAL_DELAY}ms" >> /tmp/vlc_audio_sync_completed.txt

# Copy config file for detailed verification
cp "$VLC_RC" /tmp/vlc_audio_sync_config.txt 2>/dev/null || echo "Could not copy config"

echo "=== Export Complete ==="