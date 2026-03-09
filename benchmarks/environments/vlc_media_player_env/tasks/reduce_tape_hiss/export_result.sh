#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Reduce Tape Hiss Result ==="

# Initialize result variables
AUDIO_FILTERS=""
FILTER_COUNT=0
CONFIG_FOUND="false"
RUNTIME_CAPTURED="false"

# Try to query VLC RC interface for current audio filter status
if is_vlc_running; then
    echo "Querying VLC RC interface for audio filters..."
    
    # Query status which may include filter info
    RC_OUTPUT=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_OUTPUT" ]; then
        echo "RC interface responded"
        # Log the output for debugging
        echo "$RC_OUTPUT" > /tmp/vlc_rc_status.log
        
        # Note: RC interface may not directly expose all filter settings
        # We'll primarily rely on vlcrc file for verification
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
    
    # If still running, force kill
    if is_vlc_running; then
        echo "VLC still running, force closing..."
        kill_vlc ga
        sleep 1
    fi
fi

# Read VLC configuration file to check audio filters
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration file..."
    CONFIG_FOUND="true"
    
    # Copy the entire config for verification
    cp "$VLC_RC" /tmp/vlc_config_after_task.txt
    
    # Extract audio filter settings
    FILTERS_JSON=""
    
    # Check for audio-filter setting (main filter chain)
    if grep -q "^audio-filter=" "$VLC_RC"; then
        AUDIO_FILTERS=$(grep "^audio-filter=" "$VLC_RC" | cut -d= -f2 | head -1)
        echo "Audio filters found: $AUDIO_FILTERS"
        
        if [ -n "$AUDIO_FILTERS" ]; then
            FILTERS_JSON="${FILTERS_JSON}\"audio-filter\": \"${AUDIO_FILTERS}\""
            # Count filters (separated by colons)
            FILTER_COUNT=$(echo "$AUDIO_FILTERS" | tr ':' '\n' | grep -v '^$' | wc -l)
        fi
    fi
    
    # Check for compressor settings
    COMPRESSOR_SETTINGS=$(grep "^compressor-" "$VLC_RC" 2>/dev/null || echo "")
    if [ -n "$COMPRESSOR_SETTINGS" ]; then
        [ -n "$FILTERS_JSON" ] && FILTERS_JSON="${FILTERS_JSON},"
        COMPRESSOR_COUNT=$(echo "$COMPRESSOR_SETTINGS" | wc -l)
        FILTERS_JSON="${FILTERS_JSON}\"compressor_settings\": $COMPRESSOR_COUNT"
        echo "Compressor settings found: $COMPRESSOR_COUNT entries"
    fi
    
    # Check for normalizer settings
    NORM_SETTINGS=$(grep "^norm-" "$VLC_RC" 2>/dev/null || echo "")
    if [ -n "$NORM_SETTINGS" ]; then
        [ -n "$FILTERS_JSON" ] && FILTERS_JSON="${FILTERS_JSON},"
        NORM_COUNT=$(echo "$NORM_SETTINGS" | wc -l)
        FILTERS_JSON="${FILTERS_JSON}\"normalizer_settings\": $NORM_COUNT"
        echo "Normalizer settings found: $NORM_COUNT entries"
    fi
    
    # Check for spatializer settings
    SPATIAL_SETTINGS=$(grep "^spatializer-" "$VLC_RC" 2>/dev/null || echo "")
    if [ -n "$SPATIAL_SETTINGS" ]; then
        [ -n "$FILTERS_JSON" ] && FILTERS_JSON="${FILTERS_JSON},"
        SPATIAL_COUNT=$(echo "$SPATIAL_SETTINGS" | wc -l)
        FILTERS_JSON="${FILTERS_JSON}\"spatializer_settings\": $SPATIAL_COUNT"
        echo "Spatializer settings found: $SPATIAL_COUNT entries"
    fi
    
    # Check for equalizer settings
    EQ_SETTINGS=$(grep "^equalizer-" "$VLC_RC" 2>/dev/null || echo "")
    if [ -n "$EQ_SETTINGS" ]; then
        [ -n "$FILTERS_JSON" ] && FILTERS_JSON="${FILTERS_JSON},"
        EQ_COUNT=$(echo "$EQ_SETTINGS" | wc -l)
        FILTERS_JSON="${FILTERS_JSON}\"equalizer_settings\": $EQ_COUNT"
        echo "Equalizer settings found: $EQ_COUNT entries"
    fi
    
    # Build final JSON
    if [ -n "$FILTERS_JSON" ]; then
        FILTERS_JSON="{${FILTERS_JSON}}"
    else
        FILTERS_JSON="{}"
    fi
else
    echo "⚠️ VLC config file not found"
    FILTERS_JSON="{}"
fi

# Write comprehensive JSON result file
cat > /tmp/vlc_noise_reduction_result.json <<EOFJSON
{
    "config_found": $CONFIG_FOUND,
    "audio_filters": "$AUDIO_FILTERS",
    "filter_count": $FILTER_COUNT,
    "filter_details": $FILTERS_JSON,
    "runtime_captured": $RUNTIME_CAPTURED,
    "source": "vlcrc"
}
EOFJSON

echo "✅ Noise reduction result saved to /tmp/vlc_noise_reduction_result.json"
cat /tmp/vlc_noise_reduction_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_noise_reduction_completed.txt
echo "Noise reduction task completed" >> /tmp/vlc_noise_reduction_completed.txt
echo "Audio filters configured: $FILTER_COUNT" >> /tmp/vlc_noise_reduction_completed.txt

# Create a summary file with extracted audio filter settings
cat > /tmp/vlc_audio_filters_summary.txt <<EOFSUM
=== VLC Audio Filter Configuration Summary ===
Date: $(date)

Audio Filter Chain: $AUDIO_FILTERS
Number of Filters: $FILTER_COUNT

Filter Details:
$FILTERS_JSON

Config File Found: $CONFIG_FOUND
EOFSUM

echo "✅ Summary saved to /tmp/vlc_audio_filters_summary.txt"

echo "=== Export Complete ==="