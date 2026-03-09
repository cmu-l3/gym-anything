#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Correct Color Space Result ==="

# Copy VLC config file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ Copying VLC config..."
    cp "$VLC_RC" /tmp/vlc_colorspace_config.txt
    
    # Show relevant color adjustment settings
    echo "Current color adjustment settings:"
    grep -E "video-filter|adjust-" "$VLC_RC" || echo "No adjustment settings found"
else
    echo "⚠️ VLC config not found at $VLC_RC"
fi

# Check for any snapshots taken (optional verification)
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
LATEST_SNAPSHOT=$(ls -t "$SNAPSHOT_DIR"/vlc-snap* 2>/dev/null | head -1)

if [ -n "$LATEST_SNAPSHOT" ]; then
    echo "✅ Snapshot found: $LATEST_SNAPSHOT"
    cp "$LATEST_SNAPSHOT" /tmp/vlc_colorspace_snapshot.png
else
    echo "ℹ️ No snapshot found (optional)"
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

# Ensure VLC is fully closed
if is_vlc_running; then
    echo "Forcefully closing VLC..."
    kill_vlc ga
    sleep 1
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_colorspace_completed.txt
echo "Color space correction task completed" >> /tmp/vlc_colorspace_completed.txt

echo "=== Export Complete ==="