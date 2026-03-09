#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adjust Audio Balance Result ==="

# Initialize variables
BALANCE_VALUE=""
BALANCE_SOURCE=""
EFFECTS_ENABLED="false"
RUNTIME_CAPTURED="false"

# Try to query VLC RC interface for current audio settings
if is_vlc_running; then
    echo "Querying VLC RC interface for audio balance..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract audio balance/stereo information
        # Note: RC interface may not expose balance directly, so this is a best-effort attempt
        AUDIO_INFO=$(echo "$RC_OUTPUT" | grep -i "audio\|stereo\|balance" || echo "")

        if [ -n "$AUDIO_INFO" ]; then
            echo "Audio info from RC: $AUDIO_INFO"
            # Try to extract balance value if present
            BALANCE_FROM_RC=$(echo "$AUDIO_INFO" | grep -oP 'balance[:\s]*\K[-+]?[0-9]*\.?[0-9]+' | head -1 || echo "")
            if [ -n "$BALANCE_FROM_RC" ]; then
                BALANCE_VALUE="$BALANCE_FROM_RC"
                BALANCE_SOURCE="rc"
                RUNTIME_CAPTURED="true"
                echo "✅ Captured balance from VLC RC: $BALANCE_VALUE"
            fi
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC gracefully to ensure config is written
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
            sleep 0.5
        fi
        echo "Closing VLC to flush configuration..."
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2

        # Force kill if still running
        if is_vlc_running; then
            echo "VLC still running, force closing..."
            kill_vlc ga
            sleep 1
        fi
    } || {
        echo "⚠️ Failed to close VLC gracefully; force killing"
        kill_vlc ga
        sleep 1
    }
fi

# Primary source: Read VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"
BALANCE_FOUND="false"
BALANCE_KEYS_CHECKED=()

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration file: $VLC_RC"

    # Check multiple possible balance configuration keys (VLC versions vary)
    BALANCE_KEY_VARIANTS=(
        "audio-stereo-balance"
        "audio-channel-mixer-balance"
        "spatializer-balance"
        "stereo-widen-balance"
        "headphone-balance"
        "audio-balance"
    )

    for key in "${BALANCE_KEY_VARIANTS[@]}"; do
        BALANCE_KEYS_CHECKED+=("$key")
        if grep -q "^${key}=" "$VLC_RC"; then
            VALUE=$(grep "^${key}=" "$VLC_RC" | cut -d= -f2 | head -1)
            if [ -n "$VALUE" ]; then
                BALANCE_VALUE="$VALUE"
                BALANCE_SOURCE="${key}"
                BALANCE_FOUND="true"
                echo "✅ Found balance setting: ${key}=${VALUE}"
                break
            fi
        fi
    done

    if [ "$BALANCE_FOUND" = "false" ]; then
        echo "⚠️ No balance setting found in vlcrc"
        echo "Checked keys: ${BALANCE_KEYS_CHECKED[*]}"
    fi

    # Check if audio effects/filters are enabled
    if grep -qE "^(audio-filter|audio-visual)" "$VLC_RC"; then
        EFFECTS_ENABLED="true"
        echo "Audio effects/filters detected in config"
    fi

    # Copy vlcrc for detailed verification
    cp "$VLC_RC" /tmp/vlc_vlcrc_backup.txt || true
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Determine final balance value
if [ -z "$BALANCE_VALUE" ]; then
    BALANCE_VALUE="0.0"
    BALANCE_SOURCE="default"
    echo "⚠️ No balance adjustment detected, using default: 0.0"
fi

# Write JSON result file
cat > /tmp/vlc_balance_result.json <<EOF
{
    "balance_value": "$BALANCE_VALUE",
    "balance_source": "$BALANCE_SOURCE",
    "balance_found": $BALANCE_FOUND,
    "effects_enabled": $EFFECTS_ENABLED,
    "runtime_captured": $RUNTIME_CAPTURED,
    "keys_checked": [$(printf '"%s",' "${BALANCE_KEYS_CHECKED[@]}" | sed 's/,$//')]
}
EOF

echo "✅ Balance result saved to /tmp/vlc_balance_result.json"
cat /tmp/vlc_balance_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_balance_completed.txt
echo "Balance value: $BALANCE_VALUE" >> /tmp/vlc_balance_completed.txt
echo "Source: $BALANCE_SOURCE" >> /tmp/vlc_balance_completed.txt

echo "=== Export Complete ==="