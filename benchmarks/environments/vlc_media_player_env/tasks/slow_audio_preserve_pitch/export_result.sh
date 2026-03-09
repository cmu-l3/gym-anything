#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Slow Audio Preserve Pitch Result ==="

# Query VLC RC interface for current playback rate
RUNTIME_RATE=""
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for playback rate..."
    
    # Try to get current playback rate from RC interface
    # The 'get_time' command returns time, but we need rate
    # Try 'status' command which includes rate information
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract rate from status output
        # VLC RC status may show "rate: X" or similar
        RUNTIME_RATE=$(echo "$RC_OUTPUT" | grep -oP '(?:rate|speed):\s*\K[\d.]+' | head -1)
        
        if [ -n "$RUNTIME_RATE" ]; then
            RUNTIME_CAPTURED="true"
            echo "✓ Captured playback rate from VLC RC: $RUNTIME_RATE"
        else
            echo "⚠ Could not extract rate from RC status"
        fi
    else
        echo "⚠ Could not query RC interface"
    fi
fi

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    
    # Close via RC interface first (cleaner)
    echo "quit" | nc -w 1 localhost 9999 > /dev/null 2>&1 || true
    sleep 2
    
    # Fallback to keyboard shortcut if still running
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    fi
    
    # Final fallback to kill
    if is_vlc_running; then
        kill_vlc ga
        sleep 1
    fi
    
    echo "✓ VLC closed"
fi

# Wait for config to be written
sleep 1

# Copy VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✓ VLC config file found"
    cp "$VLC_RC" /tmp/vlc_slow_audio_config.txt
    
    # Extract relevant settings for debugging
    echo ""
    echo "=== Relevant Config Settings ==="
    grep -E "^(rate|audio-time-stretch|scaletempo|audio-filter|playback-speed)=" "$VLC_RC" || echo "  (no rate/audio settings found)"
    echo "==="
else
    echo "⚠ VLC config file not found at $VLC_RC"
    touch /tmp/vlc_slow_audio_config.txt
fi

# Create result JSON with both runtime and config info
cat > /tmp/vlc_slow_audio_result.json <<EOF
{
    "runtime_rate": "$RUNTIME_RATE",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✓ Result JSON saved"
cat /tmp/vlc_slow_audio_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_slow_audio_completed.txt
echo "Task completed - playback speed configuration" >> /tmp/vlc_slow_audio_completed.txt

echo ""
echo "=== Export Complete ==="