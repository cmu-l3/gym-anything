#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix TV Overscan Result ==="

# Initialize result variables
FILTER_ENABLED="false"
FILTER_NAME=""
CANVAS_CONFIG=""
PADDING_CONFIG=""
CONFIG_FOUND="false"

# Try to capture runtime VLC state if RC interface is available
# (Canvas filter settings aren't easily queryable via RC, so we'll mainly rely on config)

# Close VLC to ensure config is written
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3  # Give VLC time to write config
fi

# Read VLC config file
VLCRC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLCRC" ]; then
    echo "Reading VLC configuration from: $VLCRC"
    CONFIG_FOUND="true"
    
    # Check for video filters
    VIDEO_FILTER=$(grep "^video-filter=" "$VLCRC" | cut -d= -f2 || echo "")
    VOUT_FILTER=$(grep "^vout-filter=" "$VLCRC" | cut -d= -f2 || echo "")
    
    echo "Video filters: $VIDEO_FILTER"
    echo "Vout filters: $VOUT_FILTER"
    
    # Check if canvas or padding-related filters are enabled
    if echo "$VIDEO_FILTER" | grep -q "canvas\|pad\|transform"; then
        FILTER_ENABLED="true"
        FILTER_NAME=$(echo "$VIDEO_FILTER" | grep -o "canvas\|pad\|transform" | head -1)
        echo "✅ Filter detected in video-filter: $FILTER_NAME"
    fi
    
    if echo "$VOUT_FILTER" | grep -q "canvas\|pad\|transform"; then
        FILTER_ENABLED="true"
        FILTER_NAME=$(echo "$VOUT_FILTER" | grep -o "canvas\|pad\|transform" | head -1)
        echo "✅ Filter detected in vout-filter: $FILTER_NAME"
    fi
    
    # Extract canvas-related parameters
    CANVAS_PARAMS=""
    for param in canvas-width canvas-height canvas-aspect canvas-padd canvas-padding transform-type; do
        if grep -q "^${param}=" "$VLCRC"; then
            VALUE=$(grep "^${param}=" "$VLCRC" | cut -d= -f2 | head -1)
            CANVAS_PARAMS="${CANVAS_PARAMS}\"${param}\": \"${VALUE}\", "
            echo "  - ${param}: ${VALUE}"
        fi
    done
    
    # Remove trailing comma
    CANVAS_PARAMS=$(echo "$CANVAS_PARAMS" | sed 's/, $//')
    
    if [ -n "$CANVAS_PARAMS" ]; then
        CANVAS_CONFIG="{${CANVAS_PARAMS}}"
        PADDING_CONFIG="configured"
        echo "✅ Canvas/padding configuration found"
    else
        echo "⚠️ No canvas/padding parameters found in config"
    fi
    
    # Copy vlcrc for verification
    cp "$VLCRC" /tmp/vlc_overscan_vlcrc.txt
    echo "Copied vlcrc to /tmp/vlc_overscan_vlcrc.txt"
    
else
    echo "⚠️ VLC config file not found: $VLCRC"
fi

# Write JSON result file
cat > /tmp/vlc_overscan_result.json <<EOF
{
    "filter_enabled": $FILTER_ENABLED,
    "filter_name": "$FILTER_NAME",
    "canvas_config": $( [ -n "$CANVAS_CONFIG" ] && echo "\"$CANVAS_CONFIG\"" || echo "\"{}\"" ),
    "padding_configured": "$PADDING_CONFIG",
    "config_found": $CONFIG_FOUND,
    "vlcrc_path": "$VLCRC"
}
EOF

echo "✅ Overscan result saved to /tmp/vlc_overscan_result.json"
cat /tmp/vlc_overscan_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_overscan_completed.txt
echo "Filter enabled: ${FILTER_ENABLED}" >> /tmp/vlc_overscan_completed.txt
echo "Configuration found: ${CONFIG_FOUND}" >> /tmp/vlc_overscan_completed.txt

echo "=== Export Complete ==="