#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Mirror Video Horizontal Result ==="

VLC_CONFIG="/home/ga/.config/vlc/vlcrc"
EXPORT_BASE="/tmp/vlc_mirror_result"

# Ensure VLC settings are flushed to disk
if is_vlc_running; then
    echo "VLC is running, waiting for config to be written..."
    sleep 2
fi

# Export VLC configuration file
if [ -f "$VLC_CONFIG" ]; then
    echo "✅ VLC config found, copying..."
    cp "$VLC_CONFIG" "${EXPORT_BASE}_vlcrc"
    
    # Log relevant settings for debugging
    echo "=== Relevant VLC Settings ==="
    grep -E "video-filter|vout-filter|transform" "$VLC_CONFIG" || echo "No transform settings found"
    echo "=========================="
else
    echo "⚠️ VLC config not found at $VLC_CONFIG"
    echo "missing_config" > "${EXPORT_BASE}_vlcrc"
fi

# Close VLC gracefully
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "VLC still running, force killing..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_mirror_completed.txt
echo "Mirror video horizontal task completed" >> /tmp/vlc_mirror_completed.txt

echo "=== Export Complete ==="
echo "Config exported to: ${EXPORT_BASE}_vlcrc"