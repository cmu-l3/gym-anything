#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Adjust Stereo Balance Result ==="

# Query VLC RC interface for audio filter settings
AUDIO_FILTERS=""
FILTERS_CAPTURED="false"
EFFECTS_JSON="{}"
EFFECTS_COUNT=0

if is_vlc_running; then
    echo "Querying VLC RC interface for audio filters..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract audio filter info from status
        AUDIO_FILTERS=$(echo "$RC_OUTPUT" | grep -i "audio.*filter" || echo "")

        if [ -n "$AUDIO_FILTERS" ]; then
            FILTERS_CAPTURED="true"
            echo "✅ Captured audio filters from RC: $AUDIO_FILTERS"
        fi
    else
        echo "⚠️ Could not query RC interface"
    fi
fi

# Close VLC gracefully
if is_vlc_running; then
    {
        wid=$(get_vlc_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid" || true
        fi
        echo "Closing VLC..."
        safe_xdotool ga :1 key --delay 200 ctrl+q
        sleep 2
    } || {
        echo "⚠️ Failed to close VLC gracefully"
    }
fi

# Ensure VLC is fully closed to flush config
sleep 1
if is_vlc_running; then
    echo "VLC still running, force killing..."
    kill_vlc ga
    sleep 1
fi

# Read VLC config file for audio effect settings
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading audio effect settings from vlcrc..."

    # Look for audio effect related settings
    AUDIO_FILTER_LINE=$(grep "^audio-filter=" "$VLC_RC" || echo "")
    SPATIALIZER_SETTINGS=$(grep "^spatializer-" "$VLC_RC" || echo "")
    HEADPHONE_SETTINGS=$(grep "^headphone-" "$VLC_RC" || echo "")
    EQUALIZER_SETTINGS=$(grep "^equalizer-" "$VLC_RC" || echo "")
    COMPRESSOR_SETTINGS=$(grep "^compressor-" "$VLC_RC" || echo "")
    PARAM_EQ_SETTINGS=$(grep "^param-eq-" "$VLC_RC" || echo "")

    # Build effects JSON
    EFFECTS_JSON_PARTS=""

    if [ -n "$AUDIO_FILTER_LINE" ]; then
        VALUE=$(echo "$AUDIO_FILTER_LINE" | cut -d= -f2)
        EFFECTS_JSON_PARTS="\"audio-filter\": \"${VALUE}\""
        EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
    fi

    # Add spatializer settings
    if [ -n "$SPATIALIZER_SETTINGS" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                [ -n "$EFFECTS_JSON_PARTS" ] && EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS},"
                EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS}\"${KEY}\": \"${VALUE}\""
                EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
            fi
        done <<< "$SPATIALIZER_SETTINGS"
    fi

    # Add headphone settings
    if [ -n "$HEADPHONE_SETTINGS" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                [ -n "$EFFECTS_JSON_PARTS" ] && EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS},"
                EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS}\"${KEY}\": \"${VALUE}\""
                EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
            fi
        done <<< "$HEADPHONE_SETTINGS"
    fi

    # Add equalizer settings
    if [ -n "$EQUALIZER_SETTINGS" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                [ -n "$EFFECTS_JSON_PARTS" ] && EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS},"
                EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS}\"${KEY}\": \"${VALUE}\""
                EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
            fi
        done <<< "$EQUALIZER_SETTINGS"
    fi

    # Add compressor settings
    if [ -n "$COMPRESSOR_SETTINGS" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                [ -n "$EFFECTS_JSON_PARTS" ] && EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS},"
                EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS}\"${KEY}\": \"${VALUE}\""
                EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
            fi
        done <<< "$COMPRESSOR_SETTINGS"
    fi

    # Add parametric EQ settings
    if [ -n "$PARAM_EQ_SETTINGS" ]; then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                [ -n "$EFFECTS_JSON_PARTS" ] && EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS},"
                EFFECTS_JSON_PARTS="${EFFECTS_JSON_PARTS}\"${KEY}\": \"${VALUE}\""
                EFFECTS_COUNT=$((EFFECTS_COUNT + 1))
            fi
        done <<< "$PARAM_EQ_SETTINGS"
    fi

    if [ -n "$EFFECTS_JSON_PARTS" ]; then
        EFFECTS_JSON="{${EFFECTS_JSON_PARTS}}"
    fi

    echo "Found $EFFECTS_COUNT audio effect settings from vlcrc"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
fi

# Write JSON result file with all collected data
cat > /tmp/vlc_balance_result.json <<EOF
{
    "audio_effects": $EFFECTS_JSON,
    "effects_count": $EFFECTS_COUNT,
    "filters_captured": $FILTERS_CAPTURED,
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "source": "vlcrc"
}
EOF

echo "✅ Audio balance result saved to /tmp/vlc_balance_result.json"
cat /tmp/vlc_balance_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_balance_completed.txt
echo "Stereo balance adjustment task completed" >> /tmp/vlc_balance_completed.txt

echo "=== Export Complete ==="