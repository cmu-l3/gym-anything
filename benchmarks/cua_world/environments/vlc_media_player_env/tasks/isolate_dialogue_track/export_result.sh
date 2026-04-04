#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Isolate Dialogue Track Result ==="

# Query VLC RC interface for audio filter settings
AUDIO_FILTERS=""
FILTER_SETTINGS="{}"
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "Querying VLC RC interface for audio filters..."

    # Query status from RC interface
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")

    if [ -n "$RC_OUTPUT" ]; then
        # Try to extract audio filter information from status
        AUDIO_FILTER_LINE=$(echo "$RC_OUTPUT" | grep -i "audio" || echo "")
        
        if [ -n "$AUDIO_FILTER_LINE" ]; then
            echo "Audio filter info from RC: $AUDIO_FILTER_LINE"
        fi
    fi
fi

# Close VLC gracefully to ensure config is written
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to save configuration..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3
fi

# Read VLC config file for audio filter settings (primary verification method)
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading audio filter settings from vlcrc..."
    
    # Create JSON of all audio-related settings
    FILTER_SETTINGS_PARTS=()
    
    # Check for audio-filter setting
    if grep -q "^audio-filter=" "$VLC_RC"; then
        AUDIO_FILTER=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2 | head -1)
        FILTER_SETTINGS_PARTS+=("\"audio-filter\": \"$AUDIO_FILTER\"")
        echo "Found audio-filter: $AUDIO_FILTER"
    fi
    
    # Check for headphone effect settings
    if grep -q "^headphone-" "$VLC_RC"; then
        HEADPHONE_SETTINGS=$(grep "^headphone-" "$VLC_RC" | head -5)
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                FILTER_SETTINGS_PARTS+=("\"$KEY\": \"$VALUE\"")
                echo "Found $KEY: $VALUE"
            fi
        done <<< "$HEADPHONE_SETTINGS"
    fi
    
    # Check for spatializer settings
    if grep -q "^spatializer" "$VLC_RC"; then
        SPATIALIZER_SETTINGS=$(grep "^spatializer" "$VLC_RC" | head -5)
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                KEY=$(echo "$line" | cut -d= -f1)
                VALUE=$(echo "$line" | cut -d= -f2)
                FILTER_SETTINGS_PARTS+=("\"$KEY\": \"$VALUE\"")
                echo "Found $KEY: $VALUE"
            fi
        done <<< "$SPATIALIZER_SETTINGS"
    fi
    
    # Check for stereo mode or channel mixer
    for setting in stereo-mode audio-channel-mixer amem-channels; do
        if grep -q "^${setting}=" "$VLC_RC"; then
            VALUE=$(grep "^${setting}=" "$VLC_RC" | cut -d= -f2 | head -1)
            FILTER_SETTINGS_PARTS+=("\"${setting}\": \"$VALUE\"")
            echo "Found ${setting}: $VALUE"
        fi
    done
    
    # Build final JSON
    if [ ${#FILTER_SETTINGS_PARTS[@]} -gt 0 ]; then
        # Join array elements with commas
        FILTER_SETTINGS_STR=$(IFS=,; echo "${FILTER_SETTINGS_PARTS[*]}")
        FILTER_SETTINGS="{$FILTER_SETTINGS_STR}"
    fi
    
    echo "Audio filter settings found: ${#FILTER_SETTINGS_PARTS[@]} entries"
else
    echo "⚠️ VLC config file not found at $VLC_RC"
fi

# Copy the vlcrc file for detailed analysis
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_dialogue_vlcrc.txt
    echo "✅ VLC config copied for verification"
fi

# Write JSON result file
cat > /tmp/vlc_dialogue_result.json <<EOF
{
    "filter_settings": $FILTER_SETTINGS,
    "settings_count": ${#FILTER_SETTINGS_PARTS[@]},
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Dialogue isolation result saved to /tmp/vlc_dialogue_result.json"
cat /tmp/vlc_dialogue_result.json

echo "$(date)" > /tmp/vlc_dialogue_completed.txt
echo "Audio filter configuration task completed" >> /tmp/vlc_dialogue_completed.txt

echo "=== Export Complete ==="