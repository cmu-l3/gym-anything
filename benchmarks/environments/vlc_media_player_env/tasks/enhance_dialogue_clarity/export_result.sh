#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enhance Dialogue Clarity Result ==="

# Query VLC RC interface for audio effects settings
AUDIO_FILTERS=""
EFFECTS_JSON="{}"
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio settings..."

    # Query afilter (audio filter) from RC interface
    RC_OUTPUT=$(echo "afilter" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Extract audio filter list
        AUDIO_FILTERS=$(echo "$RC_OUTPUT" | grep -oP '(?:audio filter:|>)\s*\K.*' | head -1)

        if [ -n "$AUDIO_FILTERS" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio filters from VLC RC: $AUDIO_FILTERS"
        fi
    else
        echo "⚠️ Could not query RC interface for audio filters"
    fi

    # Query status for more detailed info
    STATUS_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$STATUS_OUTPUT" ]; then
        echo "VLC status captured for analysis"
    fi
fi

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Give VLC a moment to process any pending UI actions
    sleep 1
    
    # Close via RC interface first (cleaner)
    echo "quit" | nc -w 1 localhost 9999 > /dev/null 2>&1 || true
    sleep 2
    
    # Fallback to keyboard if still running
    if is_vlc_running; then
        safe_xdotool ga :1 key --delay 200 ctrl+q || true
        sleep 2
    fi
    
    # Final fallback: kill process
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Give filesystem time to sync config file
sleep 1

# Copy VLC config file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ Copying VLC configuration file"
    cp "$VLC_RC" /tmp/vlc_dialogue_config.txt
    
    # Extract relevant audio settings for quick reference
    echo "=== Audio Settings in Config ===" > /tmp/vlc_dialogue_summary.txt
    grep -E "^(audio-filter|compressor|norm|equalizer|volume)" "$VLC_RC" >> /tmp/vlc_dialogue_summary.txt || echo "No audio settings found" >> /tmp/vlc_dialogue_summary.txt
    
    echo "Configuration summary:"
    cat /tmp/vlc_dialogue_summary.txt
else
    echo "⚠️ VLC config file not found at $VLC_RC"
    echo "Config file missing" > /tmp/vlc_dialogue_config.txt
fi

# Write JSON result file with runtime and config info
cat > /tmp/vlc_dialogue_result.json <<EOF
{
    "runtime_filters": "$AUDIO_FILTERS",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "config_copied": $([ -f /tmp/vlc_dialogue_config.txt ] && echo "true" || echo "false")
}
EOF

echo "✅ Result saved to /tmp/vlc_dialogue_result.json"
cat /tmp/vlc_dialogue_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_dialogue_completed.txt
echo "Dialogue enhancement task completed" >> /tmp/vlc_dialogue_completed.txt
echo "Config file: $([ -f "$VLC_RC" ] && echo 'found' || echo 'missing')" >> /tmp/vlc_dialogue_completed.txt

echo "=== Export Complete ==="