#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Frame-by-Frame Analysis Result ==="

# Check for snapshots in VLC directory
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
mkdir -p "$SNAPSHOT_DIR" 2>/dev/null || true

# Find the most recent snapshot
LATEST_SNAPSHOT=""

if [ -d "$SNAPSHOT_DIR" ]; then
    # Look for VLC snapshots (pattern: vlc-snap*.png)
    LATEST_SNAPSHOT=$(ls -t "$SNAPSHOT_DIR"/vlc-snap*.png 2>/dev/null | head -1)
fi

if [ -n "$LATEST_SNAPSHOT" ] && [ -f "$LATEST_SNAPSHOT" ]; then
    echo "✅ Snapshot found: $LATEST_SNAPSHOT"
    
    # Get snapshot info
    SNAPSHOT_SIZE=$(stat -f%z "$LATEST_SNAPSHOT" 2>/dev/null || stat -c%s "$LATEST_SNAPSHOT" 2>/dev/null || echo "0")
    echo "   Size: $((SNAPSHOT_SIZE / 1024)) KB"
    
    # Copy to temporary location for verification
    cp "$LATEST_SNAPSHOT" /tmp/vlc_frame_step_snapshot.png
    echo "   Copied to /tmp/vlc_frame_step_snapshot.png"
else
    echo "⚠️ No snapshot found in $SNAPSHOT_DIR"
    
    # Also check alternative locations
    ALT_SNAPSHOT=$(find /home/ga -name "vlc-snap*.png" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$ALT_SNAPSHOT" ] && [ -f "$ALT_SNAPSHOT" ]; then
        echo "Found snapshot in alternative location: $ALT_SNAPSHOT"
        cp "$ALT_SNAPSHOT" /tmp/vlc_frame_step_snapshot.png
    else
        echo "No snapshot found anywhere"
        # Create an empty marker file to avoid verification errors
        touch /tmp/vlc_frame_step_no_snapshot.txt
    fi
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
        echo "Force killing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_frame_step_completed.txt
echo "Frame-by-frame analysis task completed" >> /tmp/vlc_frame_step_completed.txt

# Log summary
if [ -f /tmp/vlc_frame_step_snapshot.png ]; then
    echo "✅ Snapshot exported successfully"
else
    echo "⚠️ No snapshot to export"
fi

echo "=== Export Complete ==="