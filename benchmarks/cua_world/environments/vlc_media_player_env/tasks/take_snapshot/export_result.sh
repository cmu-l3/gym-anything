#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Take Snapshot Result ==="

# Check for snapshot
SNAPSHOT_DIR="/home/ga/Pictures/vlc"
LATEST_SNAPSHOT=$(ls -t "$SNAPSHOT_DIR"/vlc-snap* 2>/dev/null | head -1)

if [ -n "$LATEST_SNAPSHOT" ]; then
    echo "✅ Snapshot found: $LATEST_SNAPSHOT"
    cp "$LATEST_SNAPSHOT" /tmp/vlc_take_snapshot.png
else
    echo "⚠️ Snapshot not found"
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid"
    fi
    safe_xdotool ga :1 key ctrl+q
    sleep 1
fi

echo "$(date)" > /tmp/vlc_take_snapshot_completed.txt
echo "Snapshot task completed" >> /tmp/vlc_take_snapshot_completed.txt

echo "=== Export Complete ==="
