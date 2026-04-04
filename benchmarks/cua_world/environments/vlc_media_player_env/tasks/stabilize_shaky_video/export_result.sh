#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Stabilize Shaky Video Result ==="

# Create result structure
VIDEO_FILTER=""
FILTER_FOUND="false"
TRANSFORM_TYPE=""
CONFIG_SOURCE="vlcrc"

# Read VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC configuration..."
    
    # Extract video filter settings
    if grep -q "^video-filter=" "$VLC_RC"; then
        VIDEO_FILTER=$(grep "^video-filter=" "$VLC_RC" | cut -d= -f2- | head -1)
        FILTER_FOUND="true"
        echo "✅ Video filter found: $VIDEO_FILTER"
    else
        echo "⚠️ No video-filter setting found in vlcrc"
    fi
    
    # Check for transform type if transform filter is used
    if grep -q "^transform-type=" "$VLC_RC"; then
        TRANSFORM_TYPE=$(grep "^transform-type=" "$VLC_RC" | cut -d= -f2- | head -1)
        echo "Transform type: $TRANSFORM_TYPE"
    fi
    
    # Copy entire vlcrc for verification
    cp "$VLC_RC" /tmp/vlc_stabilize_vlcrc.txt
    echo "✅ VLC config copied to /tmp/vlc_stabilize_vlcrc.txt"
else
    echo "⚠️ VLC config file not found at $VLC_RC"
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

# Write JSON result file with filter information
cat > /tmp/vlc_stabilize_result.json <<EOF
{
    "video_filter": "$VIDEO_FILTER",
    "filter_found": $FILTER_FOUND,
    "transform_type": "$TRANSFORM_TYPE",
    "config_source": "$CONFIG_SOURCE",
    "config_file_exists": $([ -f "$VLC_RC" ] && echo "true" || echo "false")
}
EOF

echo "✅ Stabilization result saved to /tmp/vlc_stabilize_result.json"
cat /tmp/vlc_stabilize_result.json

echo "$(date)" > /tmp/vlc_stabilize_completed.txt
echo "Stabilize shaky video task completed" >> /tmp/vlc_stabilize_completed.txt

echo "=== Export Complete ==="