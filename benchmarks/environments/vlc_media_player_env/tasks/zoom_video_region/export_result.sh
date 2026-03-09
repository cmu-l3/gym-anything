#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Zoom Video Region Result ==="

# VLC config file location
VLC_RC="/home/ga/.config/vlc/vlcrc"
ZOOM_SETTINGS_FOUND="false"
INTERACTIVE_ZOOM=""
ZOOM_VALUE=""

# Extract zoom settings from VLC config
if [ -f "$VLC_RC" ]; then
    echo "Reading VLC config for zoom settings..."
    
    # Extract interactive-zoom setting
    if grep -q "^interactive-zoom=" "$VLC_RC"; then
        INTERACTIVE_ZOOM=$(grep "^interactive-zoom=" "$VLC_RC" | cut -d= -f2 | head -1)
        ZOOM_SETTINGS_FOUND="true"
        echo "Found interactive-zoom: $INTERACTIVE_ZOOM"
    else
        INTERACTIVE_ZOOM="0"
        echo "interactive-zoom not found (default: 0)"
    fi
    
    # Extract zoom value
    if grep -q "^zoom=" "$VLC_RC"; then
        ZOOM_VALUE=$(grep "^zoom=" "$VLC_RC" | cut -d= -f2 | head -1)
        ZOOM_SETTINGS_FOUND="true"
        echo "Found zoom value: $ZOOM_VALUE"
    else
        ZOOM_VALUE="1.0"
        echo "zoom value not found (default: 1.0)"
    fi
    
    # Copy entire vlcrc for verification
    cp "$VLC_RC" /tmp/vlc_zoom_vlcrc.conf
    echo "✅ VLC config copied to /tmp/vlc_zoom_vlcrc.conf"
else
    echo "⚠️ VLC config file not found: $VLC_RC"
    INTERACTIVE_ZOOM="0"
    ZOOM_VALUE="1.0"
fi

# Close VLC properly
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Write JSON result file with zoom settings
cat > /tmp/vlc_zoom_result.json <<EOF
{
    "interactive_zoom": "$INTERACTIVE_ZOOM",
    "zoom_value": "$ZOOM_VALUE",
    "settings_found": $ZOOM_SETTINGS_FOUND,
    "config_path": "$VLC_RC"
}
EOF

echo "✅ Zoom result saved to /tmp/vlc_zoom_result.json"
cat /tmp/vlc_zoom_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_zoom_completed.txt
echo "Zoom video region task completed" >> /tmp/vlc_zoom_completed.txt
echo "Interactive zoom: $INTERACTIVE_ZOOM" >> /tmp/vlc_zoom_completed.txt
echo "Zoom value: $ZOOM_VALUE" >> /tmp/vlc_zoom_completed.txt

echo "=== Export Complete ==="