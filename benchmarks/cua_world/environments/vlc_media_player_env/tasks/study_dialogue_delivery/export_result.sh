#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Study Dialogue Delivery Result ==="

# Query VLC RC interface for current state (optional, best effort)
RUNTIME_INFO=""
if is_vlc_running; then
    echo "Querying VLC RC interface..."
    
    # Try to get status
    RC_STATUS=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$RC_STATUS" ]; then
        echo "VLC Status captured from RC interface"
        RUNTIME_INFO="$RC_STATUS"
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

# Copy VLC configuration file for verification
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_dialogue_config.txt
    echo "✅ VLC config copied"
else
    echo "⚠️ VLC config not found"
    touch /tmp/vlc_dialogue_config.txt
fi

# Check snapshot directory
SNAPSHOT_DIR="/home/ga/Pictures/voice_acting_reference"
SNAPSHOT_COUNT=0

if [ -d "$SNAPSHOT_DIR" ]; then
    SNAPSHOT_COUNT=$(find "$SNAPSHOT_DIR" -name "*.png" -type f 2>/dev/null | wc -l)
    echo "✅ Found $SNAPSHOT_COUNT snapshot(s) in $SNAPSHOT_DIR"
    
    # List all snapshots with details
    echo "Snapshot files:"
    ls -lh "$SNAPSHOT_DIR"/*.png 2>/dev/null || echo "No PNG files found"
    
    # Create a tar of all snapshots for verification
    if [ $SNAPSHOT_COUNT -gt 0 ]; then
        cd "$SNAPSHOT_DIR"
        tar -czf /tmp/vlc_dialogue_snapshots.tar.gz *.png 2>/dev/null || true
        cd - > /dev/null
        echo "✅ Snapshots archived to /tmp/vlc_dialogue_snapshots.tar.gz"
    fi
else
    echo "⚠️ Snapshot directory does not exist"
fi

# Write result summary JSON
cat > /tmp/vlc_dialogue_result.json <<EOF
{
    "snapshot_count": $SNAPSHOT_COUNT,
    "snapshot_dir": "$SNAPSHOT_DIR",
    "config_found": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "runtime_info_captured": $([ -n "$RUNTIME_INFO" ] && echo "true" || echo "false")
}
EOF

echo "✅ Result summary saved to /tmp/vlc_dialogue_result.json"
cat /tmp/vlc_dialogue_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_dialogue_completed.txt
echo "Study dialogue delivery task completed" >> /tmp/vlc_dialogue_completed.txt
echo "Snapshots found: $SNAPSHOT_COUNT" >> /tmp/vlc_dialogue_completed.txt

echo "=== Export Complete ==="