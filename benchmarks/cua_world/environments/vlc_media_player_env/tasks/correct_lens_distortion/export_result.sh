#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Correct Lens Distortion Result ==="

# Check for snapshot at expected location
SNAPSHOT_PATH="/home/ga/Pictures/vlc/corrected_view.png"
SNAPSHOT_FOUND="false"

if [ -f "$SNAPSHOT_PATH" ]; then
    echo "✅ Snapshot found at expected location: $SNAPSHOT_PATH"
    cp "$SNAPSHOT_PATH" /tmp/vlc_corrected_snapshot.png
    ls -lh "$SNAPSHOT_PATH"
    SNAPSHOT_FOUND="true"
else
    echo "⚠️ Snapshot not found at expected location: $SNAPSHOT_PATH"
    
    # Look for any recently created snapshot in VLC snapshot directory
    SNAPSHOT_DIR="/home/ga/Pictures/vlc"
    if [ -d "$SNAPSHOT_DIR" ]; then
        RECENT_SNAPSHOT=$(find "$SNAPSHOT_DIR" -type f \( -name "*.png" -o -name "*.jpg" \) -mmin -5 2>/dev/null | head -1)
        
        if [ -n "$RECENT_SNAPSHOT" ]; then
            echo "Found recent snapshot: $RECENT_SNAPSHOT"
            cp "$RECENT_SNAPSHOT" /tmp/vlc_corrected_snapshot.png
            SNAPSHOT_FOUND="true"
        else
            echo "⚠️ No recent snapshots found in $SNAPSHOT_DIR"
        fi
    fi
fi

# Check VLC config for geometry filters
VLC_RC="/home/ga/.config/vlc/vlcrc"
FILTERS_JSON="{}"
FILTER_COUNT=0

if [ -f "$VLC_RC" ]; then
    echo "Reading VLC config for geometry filters..."
    
    # Check for various geometry-related filters
    for filter_key in video-filter vout-filter; do
        if grep -q "^${filter_key}=" "$VLC_RC"; then
            FILTER_VALUE=$(grep "^${filter_key}=" "$VLC_RC" | cut -d= -f2- | head -1)
            
            # Check if value contains geometry-related keywords
            if echo "$FILTER_VALUE" | grep -qiE "transform|geometry|panoramix|ball|lens"; then
                FILTER_COUNT=$((FILTER_COUNT + 1))
                echo "Found geometry filter: ${filter_key}=${FILTER_VALUE}"
                
                # Build JSON (simplified - just mark as found)
                FILTERS_JSON="{\"${filter_key}\": \"${FILTER_VALUE}\"}"
            fi
        fi
    done
    
    # Copy VLC config for verification
    cp "$VLC_RC" /tmp/vlc_distortion_config.txt 2>/dev/null || true
fi

echo "Geometry filters found: $FILTER_COUNT"

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

# Write result JSON
cat > /tmp/vlc_distortion_result.json <<EOF
{
    "snapshot_found": $SNAPSHOT_FOUND,
    "filter_count": $FILTER_COUNT,
    "filters": $FILTERS_JSON
}
EOF

echo "✅ Result saved to /tmp/vlc_distortion_result.json"
cat /tmp/vlc_distortion_result.json

echo "$(date)" > /tmp/vlc_distortion_completed.txt
echo "Lens distortion correction task completed" >> /tmp/vlc_distortion_completed.txt
echo "Snapshot found: ${SNAPSHOT_FOUND}" >> /tmp/vlc_distortion_completed.txt
echo "Filters applied: ${FILTER_COUNT}" >> /tmp/vlc_distortion_completed.txt

echo "=== Export Complete ==="