#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Isolate Audio Channels Result ==="

# Query VLC RC interface for audio settings
AUDIO_SETTINGS="{}"
SETTINGS_COUNT=0
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio settings..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        echo "RC Status output:"
        echo "$RC_OUTPUT" | head -20
        
        # Try to extract audio-related settings
        AUDIO_JSON=""
        
        # Check for audio mode
        AUDIO_MODE=$(echo "$RC_OUTPUT" | grep -oP '(?:audio mode:|audio:)\s*\K[^\s\)]+' || echo "")
        if [ -n "$AUDIO_MODE" ]; then
            AUDIO_JSON="\"audio_mode\": \"${AUDIO_MODE}\""
            SETTINGS_COUNT=$((SETTINGS_COUNT + 1))
        fi
        
        # Check for stereo mode
        STEREO_MODE=$(echo "$RC_OUTPUT" | grep -oP '(?:stereo|mode):\s*\K[^\s\)]+' || echo "")
        if [ -n "$STEREO_MODE" ]; then
            [ -n "$AUDIO_JSON" ] && AUDIO_JSON="${AUDIO_JSON},"
            AUDIO_JSON="${AUDIO_JSON}\"stereo_mode\": \"${STEREO_MODE}\""
            SETTINGS_COUNT=$((SETTINGS_COUNT + 1))
        fi
        
        if [ -n "$AUDIO_JSON" ]; then
            AUDIO_SETTINGS="{${AUDIO_JSON}}"
            RUNTIME_CAPTURED="true"
            echo "✅ Captured audio settings from VLC RC: $SETTINGS_COUNT settings"
        fi
    fi
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Read VLC config
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration..."
    
    # Extract audio-related settings
    CONFIG_JSON=""
    
    for setting in audio-filter stereo-mode headphone-dim remap channelmixer audio-replay-gain-mode extrastereo; do
        if grep -q "^${setting}=" "$VLC_RC"; then
            VALUE=$(grep "^${setting}=" "$VLC_RC" | cut -d= -f2 | head -1)
            [ -n "$CONFIG_JSON" ] && CONFIG_JSON="${CONFIG_JSON},"
            CONFIG_JSON="${CONFIG_JSON}\"${setting}\": \"${VALUE}\""
            SETTINGS_COUNT=$((SETTINGS_COUNT + 1))
        fi
    done
    
    if [ -n "$CONFIG_JSON" ]; then
        if [ "$RUNTIME_CAPTURED" = "false" ]; then
            AUDIO_SETTINGS="{${CONFIG_JSON}}"
        else
            # Merge with runtime settings
            AUDIO_SETTINGS=$(echo "$AUDIO_SETTINGS" | sed 's/}$//')
            AUDIO_SETTINGS="${AUDIO_SETTINGS},${CONFIG_JSON}}"
        fi
    fi
    
    echo "Found $SETTINGS_COUNT audio settings from vlcrc"
    
    # Copy full config for verification
    cp "$VLC_RC" /tmp/vlc_channel_config.txt
    echo "✅ VLC config copied"
else
    echo "⚠️ VLC config not found"
fi

# Check for user-created test results log
TEST_LOG="/home/ga/Documents/channel_test_results.txt"
if [ -f "$TEST_LOG" ]; then
    echo "✅ Test results log found"
    cp "$TEST_LOG" /tmp/vlc_channel_test_log.txt
    cat "$TEST_LOG"
else
    echo "⚠️ Test results log not found"
    touch /tmp/vlc_channel_test_log.txt
fi

# Write JSON result file
cat > /tmp/vlc_channel_result.json <<EOF
{
    "audio_settings": $AUDIO_SETTINGS,
    "settings_count": $SETTINGS_COUNT,
    "runtime_captured": $RUNTIME_CAPTURED,
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "test_log_found": $([ -f "$TEST_LOG" ] && echo "true" || echo "false")
}
EOF

echo "✅ Channel isolation result saved to /tmp/vlc_channel_result.json"
cat /tmp/vlc_channel_result.json

echo "$(date)" > /tmp/vlc_channel_completed.txt
echo "Audio channel isolation task completed" >> /tmp/vlc_channel_completed.txt

echo "=== Export Complete ==="