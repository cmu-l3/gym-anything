#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enhance Telescope Recording Result ==="

# Check for snapshot in astronomy directory
SNAPSHOT_DIR="/home/ga/Pictures/astronomy"
EXPECTED_SNAPSHOT="$SNAPSHOT_DIR/andromeda_enhanced.png"

# Look for snapshot with expected prefix
SNAPSHOT_FILE=$(ls -t "$SNAPSHOT_DIR"/andromeda_enhanced*.png 2>/dev/null | head -1)

if [ -z "$SNAPSHOT_FILE" ]; then
    # Fallback: look for any recent PNG in the directory
    SNAPSHOT_FILE=$(find "$SNAPSHOT_DIR" -name "*.png" -mmin -5 -type f 2>/dev/null | head -1)
fi

if [ -n "$SNAPSHOT_FILE" ] && [ -f "$SNAPSHOT_FILE" ]; then
    echo "✅ Snapshot found: $SNAPSHOT_FILE"
    
    # Copy to standard location for verification
    cp "$SNAPSHOT_FILE" /tmp/vlc_telescope_snapshot.png
    
    # Also rename/copy to expected name if different
    if [ "$SNAPSHOT_FILE" != "$EXPECTED_SNAPSHOT" ]; then
        cp "$SNAPSHOT_FILE" "$EXPECTED_SNAPSHOT" 2>/dev/null || true
    fi
    
    ls -lh "$SNAPSHOT_FILE"
else
    echo "⚠️ Snapshot not found in $SNAPSHOT_DIR"
fi

# Copy VLC config for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Copying VLC config for verification..."
    cp "$VLC_RC" /tmp/vlc_telescope_config.txt
    
    # Extract adjustment filter settings for easy inspection
    echo "=== Video Adjustment Filter Settings ===" > /tmp/vlc_telescope_filters.txt
    grep -E "^(video-filter|adjust-)" "$VLC_RC" >> /tmp/vlc_telescope_filters.txt 2>/dev/null || echo "No adjustment filters found" >> /tmp/vlc_telescope_filters.txt
    
    echo "Current adjustment filter settings:"
    cat /tmp/vlc_telescope_filters.txt
else
    echo "⚠️ VLC config not found"
fi

# Query RC interface for current filter state (if VLC still running)
RUNTIME_FILTERS="{}"
if is_vlc_running; then
    echo "Querying VLC RC interface for filter state..."
    
    # Try to get status
    RC_STATUS=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    
    if [ -n "$RC_STATUS" ]; then
        echo "RC status captured"
    fi
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

# Create completion marker with metadata
cat > /tmp/vlc_telescope_completed.txt <<EOF
Task completed: $(date)
Snapshot directory: $SNAPSHOT_DIR
Snapshot file: ${SNAPSHOT_FILE:-NOT_FOUND}
VLC config: $VLC_RC
EOF

echo "✅ Task completion marker created"
cat /tmp/vlc_telescope_completed.txt

echo "=== Export Complete ==="