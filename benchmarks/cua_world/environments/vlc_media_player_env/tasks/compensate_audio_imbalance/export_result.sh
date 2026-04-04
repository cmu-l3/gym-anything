#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compensate Audio Imbalance Result ==="

# Initialize variables
BALANCE_VALUE=""
RUNTIME_CAPTURED="false"

# Query VLC RC interface for current audio balance
if is_vlc_running; then
    echo "Querying VLC RC interface for audio balance..."
    
    # Try to get balance from status output
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract balance from status output
        # VLC RC status may include "audio balance: <value>" or similar
        BALANCE_VALUE=$(echo "$RC_OUTPUT" | grep -oP '(?:audio[- ]balance|balance):\s*\K[-\d.]+' | head -1)
        
        if [ -n "$BALANCE_VALUE" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured balance from VLC RC: $BALANCE_VALUE"
        else
            echo "⚠️ Could not extract balance from RC status output"
        fi
    else
        echo "⚠️ Could not query RC interface"
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

# Fallback: Read audio balance from vlcrc if RC query failed
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -z "$BALANCE_VALUE" ] && [ -f "$VLC_RC" ]; then
    echo "Reading audio balance from vlcrc..."
    
    if grep -q "^audio-balance=" "$VLC_RC"; then
        BALANCE_VALUE=$(grep "^audio-balance=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Balance from vlcrc: $BALANCE_VALUE"
    else
        echo "⚠️ audio-balance setting not found in vlcrc"
        BALANCE_VALUE="0.0"
    fi
fi

# If still no value, default to 0.0
if [ -z "$BALANCE_VALUE" ]; then
    echo "⚠️ Could not determine balance value, defaulting to 0.0"
    BALANCE_VALUE="0.0"
fi

# Calculate balance percentage (for info only)
BALANCE_PERCENT=$(echo "scale=1; $BALANCE_VALUE * 100" | bc 2>/dev/null || echo "0")

# Check if media library or recently-used indicates playback
PLAYBACK_EVIDENCE="false"
if [ -f /home/ga/.local/share/vlc/ml.xspf ]; then
    if grep -q "audiobook_sample" /home/ga/.local/share/vlc/ml.xspf 2>/dev/null; then
        PLAYBACK_EVIDENCE="true"
    fi
fi

# Write JSON result file
cat > /tmp/vlc_balance_result.json <<EOF
{
    "balance_value": $BALANCE_VALUE,
    "balance_percent": $BALANCE_PERCENT,
    "runtime_captured": $RUNTIME_CAPTURED,
    "playback_evidence": $PLAYBACK_EVIDENCE,
    "source": "$([ "$RUNTIME_CAPTURED" = "true" ] && echo "rc" || echo "vlcrc")"
}
EOF

echo "✅ Balance result saved to /tmp/vlc_balance_result.json"
cat /tmp/vlc_balance_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_balance_completed.txt
echo "Audio balance: $BALANCE_VALUE" >> /tmp/vlc_balance_completed.txt
echo "Runtime captured: $RUNTIME_CAPTURED" >> /tmp/vlc_balance_completed.txt
echo "Playback evidence: $PLAYBACK_EVIDENCE" >> /tmp/vlc_balance_completed.txt

echo "=== Export Complete ==="