#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Visualize Exposure Issues Result ==="

# Initialize results
FILTER_ENABLED="false"
FILTER_NAMES=""
SNAPSHOT_FOUND="false"

# Check VLC config for video filters
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "Checking VLC config for video filters..."
    
    # Check for video-filter or vout-filter settings
    if grep -q "^video-filter=" "$VLC_RC" || grep -q "^vout-filter=" "$VLC_RC"; then
        FILTER_ENABLED="true"
        
        # Extract filter names
        VIDEO_FILTERS=$(grep "^video-filter=" "$VLC_RC" | cut -d= -f2 || echo "")
        VOUT_FILTERS=$(grep "^vout-filter=" "$VLC_RC" | cut -d= -f2 || echo "")
        
        FILTER_NAMES="${VIDEO_FILTERS}${VOUT_FILTERS}"
        
        echo "✅ Video filters found in config: $FILTER_NAMES"
    else
        echo "⚠️ No video filters found in VLC config"
    fi
    
    # Copy config for verification
    cp "$VLC_RC" /tmp/vlc_exposure_vlcrc.txt
else
    echo "⚠️ VLC config not found"
fi

# Check for snapshot in Pictures/vlc directory
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
LATEST_SNAPSHOT=$(find "$SNAPSHOT_DIR" -name "vlcsnap-*.png" -o -name "*.png" 2>/dev/null | sort -r | head -1)

if [ -n "$LATEST_SNAPSHOT" ] && [ -f "$LATEST_SNAPSHOT" ]; then
    echo "✅ Snapshot found: $LATEST_SNAPSHOT"
    SNAPSHOT_FOUND="true"
    cp "$LATEST_SNAPSHOT" /tmp/vlc_exposure_snapshot.png
    
    # Get snapshot info
    SNAPSHOT_SIZE=$(stat -f%z "$LATEST_SNAPSHOT" 2>/dev/null || stat -c%s "$LATEST_SNAPSHOT" 2>/dev/null || echo "0")
    SNAPSHOT_SIZE_KB=$((SNAPSHOT_SIZE / 1024))
    echo "Snapshot size: ${SNAPSHOT_SIZE_KB} KB"
else
    echo "⚠️ Snapshot not found in $SNAPSHOT_DIR"
    
    # Check alternate locations
    HOME_SNAPSHOT=$(find /home/ga/Pictures -name "*.png" -mmin -5 2>/dev/null | head -1)
    if [ -n "$HOME_SNAPSHOT" ] && [ -f "$HOME_SNAPSHOT" ]; then
        echo "Found recent snapshot: $HOME_SNAPSHOT"
        SNAPSHOT_FOUND="true"
        cp "$HOME_SNAPSHOT" /tmp/vlc_exposure_snapshot.png
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
fi

# If still running, force kill
if is_vlc_running; then
    echo "Force closing VLC..."
    kill_vlc ga
    sleep 1
fi

# Write JSON result file
cat > /tmp/vlc_exposure_result.json <<EOF
{
    "filter_enabled": $FILTER_ENABLED,
    "filter_names": "$FILTER_NAMES",
    "snapshot_found": $SNAPSHOT_FOUND,
    "snapshot_size_kb": ${SNAPSHOT_SIZE_KB:-0},
    "task_completed": true
}
EOF

echo "✅ Exposure visualization result saved to /tmp/vlc_exposure_result.json"
cat /tmp/vlc_exposure_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_exposure_completed.txt
echo "Filter enabled: $FILTER_ENABLED" >> /tmp/vlc_exposure_completed.txt
echo "Snapshot found: $SNAPSHOT_FOUND" >> /tmp/vlc_exposure_completed.txt

echo "=== Export Complete ==="