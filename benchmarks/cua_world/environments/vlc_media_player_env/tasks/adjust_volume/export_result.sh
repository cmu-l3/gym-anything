#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adjust Volume Result ==="

# Query VLC RC interface for current volume
RUNTIME_VOLUME=""
VOLUME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for volume..."

    # Query volume from RC interface
    # VLC RC returns: "status: ( audio volume: 192 )" or similar
    RC_OUTPUT=$(echo "volume" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Extract volume number from RC output
        # Format: "status: ( audio volume: 192 )" or "> 192"
        RUNTIME_VOLUME=$(echo "$RC_OUTPUT" | grep -oP '(?:audio volume: |> )\K\d+' | head -1)

        if [ -n "$RUNTIME_VOLUME" ] && [ "$RUNTIME_VOLUME" -ge 0 ] && [ "$RUNTIME_VOLUME" -le 512 ]; then
            VOLUME_CAPTURED="true"
            echo "✅ Captured volume from VLC RC: $RUNTIME_VOLUME"
        else
            echo "⚠️ Invalid volume value from RC: $RUNTIME_VOLUME"
            RUNTIME_VOLUME=""
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "Closing VLC..."
        # Can also close via RC: echo "quit" | nc localhost 9999
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    } || {
        echo "⚠️ Failed to close VLC gracefully; continuing"
    }
fi

# Fallback: Get volume from vlcrc if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"
VLCRC_VOLUME=""

if [ -z "$RUNTIME_VOLUME" ] && [ -f "$VLC_RC" ]; then
    VLCRC_VOLUME=$(grep "audio-volume=" "$VLC_RC" | cut -d= -f2 || echo "256")
    echo "Fallback to volume from vlcrc: $VLCRC_VOLUME"
fi

# Use runtime volume if captured, otherwise fallback to vlcrc
FINAL_VOLUME="${RUNTIME_VOLUME:-${VLCRC_VOLUME:-256}}"

# Write JSON result file
cat > /tmp/vlc_volume_result.json <<EOF
{
    "volume": $FINAL_VOLUME,
    "volume_percent": $(echo "scale=1; $FINAL_VOLUME / 256 * 100" | bc),
    "runtime_captured": $VOLUME_CAPTURED,
    "source": "$([ "$VOLUME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Volume result saved to /tmp/vlc_volume_result.json"
cat /tmp/vlc_volume_result.json

echo "$(date)" > /tmp/vlc_volume_completed.txt
echo "Runtime volume captured: ${VOLUME_CAPTURED}" >> /tmp/vlc_volume_completed.txt

echo "=== Export Complete ==="
