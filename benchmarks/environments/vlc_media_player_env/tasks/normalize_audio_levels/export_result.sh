#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting VLC Audio Normalization Task Results ==="

# Initialize result variables
AUDIO_FILTER=""
AUDIO_FILTER_FOUND="false"
RUNTIME_CAPTURED="false"

# Try to query VLC RC interface for current audio filter settings
if is_vlc_running; then
    echo "Querying VLC RC interface for audio filter status..."
    
    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract audio filter information from status
        # VLC RC status may show active filters
        FILTER_INFO=$(echo "$RC_OUTPUT" | grep -i "audio.*filter\|compressor\|normaliz" || echo "")
        
        if [ -n "$FILTER_INFO" ]; then
            AUDIO_FILTER="$FILTER_INFO"
            AUDIO_FILTER_FOUND="true"
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio filter info from RC: $FILTER_INFO"
        else
            echo "⚠️ No audio filter info found in RC status"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC gracefully to ensure config is saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
        sleep 0.5
    fi
    
    echo "Closing VLC to save configuration..."
    
    # Try graceful close via RC first
    echo "quit" | nc -w 1 localhost 9999 >/dev/null 2>&1 || true
    sleep 2
    
    # If still running, use keyboard shortcut
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q || true
        sleep 2
    fi
    
    # Final fallback: force kill
    if is_vlc_running; then
        echo "⚠️ Force killing VLC..."
        kill_vlc ga
        sleep 1
    fi
    
    echo "VLC closed"
fi

# Give VLC time to write config file
sleep 1

# Copy VLC configuration file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [[ -f "$VLC_RC" ]]; then
    echo "Copying VLC config file..."
    cp "$VLC_RC" /tmp/vlc_audio_norm_vlcrc.txt
    
    # Extract relevant audio settings for logging
    echo ""
    echo "=== Audio-related settings in vlcrc ==="
    grep -E "^(audio-filter|norm-max-level|normvol|compressor|audio-time-stretch)" "$VLC_RC" || echo "(no audio filter settings found)"
    echo "==================================="
    echo ""
    
    echo "✅ VLC config exported to /tmp/vlc_audio_norm_vlcrc.txt"
else
    echo "⚠️ WARNING: VLC config file not found at $VLC_RC"
    echo "This may indicate VLC did not save settings properly"
fi

# Also copy the entire VLC config directory for debugging
if [[ -d /home/ga/.config/vlc ]]; then
    tar -czf /tmp/vlc_config_backup.tar.gz -C /home/ga/.config vlc/ 2>/dev/null || true
    echo "VLC config directory archived"
fi

# Create a summary JSON for easier parsing
cat > /tmp/vlc_audio_norm_result.json <<EOF
{
    "runtime_audio_filter": "$AUDIO_FILTER",
    "audio_filter_found": $AUDIO_FILTER_FOUND,
    "runtime_captured": $RUNTIME_CAPTURED,
    "vlcrc_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Result summary saved to /tmp/vlc_audio_norm_result.json"
cat /tmp/vlc_audio_norm_result.json

# Create completion marker
echo "$(date -Iseconds)" > /tmp/vlc_audio_norm_completed.txt
echo "Audio normalization task export completed" >> /tmp/vlc_audio_norm_completed.txt

# Copy task setup log if it exists
if [[ -f /tmp/vlc_audio_norm_task.log ]]; then
    cp /tmp/vlc_audio_norm_task.log /tmp/vlc_audio_norm_setup.log
fi

echo ""
echo "=== Export Complete ==="
echo "Exported files:"
echo "  - /tmp/vlc_audio_norm_vlcrc.txt (VLC config)"
echo "  - /tmp/vlc_audio_norm_result.json (summary)"
echo "  - /tmp/vlc_audio_norm_completed.txt (completion marker)"
echo ""