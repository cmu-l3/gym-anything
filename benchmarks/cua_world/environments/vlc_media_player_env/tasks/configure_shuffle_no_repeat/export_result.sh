#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Shuffle No Repeat Result ==="

# Query VLC RC interface for playback mode settings
SHUFFLE_ENABLED="unknown"
LOOP_MODE="unknown"
REPEAT_MODE="unknown"
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for playback modes..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to parse playback mode info from status
        # VLC RC status may show random/loop/repeat status
        
        # Check for random/shuffle
        if echo "$RC_OUTPUT" | grep -iq "random.*on\|shuffle.*on\|random.*1"; then
            SHUFFLE_ENABLED="true"
        elif echo "$RC_OUTPUT" | grep -iq "random.*off\|shuffle.*off\|random.*0"; then
            SHUFFLE_ENABLED="false"
        fi

        # Check for loop mode
        if echo "$RC_OUTPUT" | grep -iq "loop.*on\|loop.*1"; then
            LOOP_MODE="true"
        elif echo "$RC_OUTPUT" | grep -iq "loop.*off\|loop.*0"; then
            LOOP_MODE="false"
        fi

        # Check for repeat mode
        if echo "$RC_OUTPUT" | grep -iq "repeat.*on\|repeat.*1"; then
            REPEAT_MODE="true"
        elif echo "$RC_OUTPUT" | grep -iq "repeat.*off\|repeat.*0"; then
            REPEAT_MODE="false"
        fi

        if [ "$SHUFFLE_ENABLED" != "unknown" ]; then
            RUNTIME_CAPTURED="true"
            echo "✅ Captured playback modes from VLC RC"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Copy VLC config file (primary verification source)
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_shuffle_config.txt
    echo "✅ Copied VLC config file"
else
    echo "⚠️ VLC config file not found"
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

# Write JSON result file with captured runtime data
cat > /tmp/vlc_shuffle_result.json <<EOF
{
    "shuffle_enabled": "$SHUFFLE_ENABLED",
    "loop_mode": "$LOOP_MODE",
    "repeat_mode": "$REPEAT_MODE",
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_file_copied": $([ -f /tmp/vlc_shuffle_config.txt ] && echo "true" || echo "false")
}
EOF

echo "✅ Shuffle configuration result saved"
cat /tmp/vlc_shuffle_result.json

echo "$(date)" > /tmp/vlc_shuffle_completed.txt
echo "Shuffle configuration task completed" >> /tmp/vlc_shuffle_completed.txt

echo "=== Export Complete ==="