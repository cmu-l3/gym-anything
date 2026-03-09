#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Frame Analysis Result ==="

# Check for snapshot at expected location
EXPECTED_SNAPSHOT="/home/ga/Pictures/analysis_frame.png"
FOUND_SNAPSHOT=""

if [ -f "$EXPECTED_SNAPSHOT" ]; then
    echo "✅ Snapshot found at expected location: $EXPECTED_SNAPSHOT"
    FOUND_SNAPSHOT="$EXPECTED_SNAPSHOT"
else
    echo "⚠️ Snapshot not found at expected location: $EXPECTED_SNAPSHOT"
    
    # Check for VLC's default snapshot naming pattern
    echo "Searching for VLC snapshots in Pictures directory..."
    
    # Look for most recent vlcsnap file
    RECENT_SNAPSHOT=$(find /home/ga/Pictures -name "vlc-snap*.png" -o -name "vlcsnap*.png" -type f -mmin -10 2>/dev/null | sort -r | head -1)
    
    if [ -n "$RECENT_SNAPSHOT" ]; then
        echo "Found recent VLC snapshot: $RECENT_SNAPSHOT"
        FOUND_SNAPSHOT="$RECENT_SNAPSHOT"
    else
        echo "⚠️ No recent VLC snapshots found"
        
        # Check if any PNG exists in Pictures
        ANY_PNG=$(find /home/ga/Pictures -name "*.png" -type f -mmin -10 2>/dev/null | head -1)
        if [ -n "$ANY_PNG" ]; then
            echo "Found recent PNG: $ANY_PNG"
            FOUND_SNAPSHOT="$ANY_PNG"
        fi
    fi
fi

# Copy snapshot to /tmp for verification if found
if [ -n "$FOUND_SNAPSHOT" ] && [ -f "$FOUND_SNAPSHOT" ]; then
    cp "$FOUND_SNAPSHOT" /tmp/vlc_frame_snapshot.png
    echo "✅ Snapshot copied to /tmp/vlc_frame_snapshot.png"
    ls -lh "$FOUND_SNAPSHOT"
    
    # Log file info
    file "$FOUND_SNAPSHOT" > /tmp/vlc_frame_snapshot_info.txt 2>&1 || true
else
    echo "❌ No snapshot file found to export"
    echo "not_found" > /tmp/vlc_frame_snapshot_status.txt
fi

# List all files in Pictures directory for debugging
echo "Contents of /home/ga/Pictures:"
ls -lah /home/ga/Pictures/ > /tmp/vlc_frame_pictures_dir.txt 2>&1 || echo "Directory listing failed"
cat /tmp/vlc_frame_pictures_dir.txt

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
echo "$(date)" > /tmp/vlc_frame_completed.txt
echo "Frame analysis task export completed" >> /tmp/vlc_frame_completed.txt
echo "Snapshot found: $([ -n "$FOUND_SNAPSHOT" ] && echo "YES" || echo "NO")" >> /tmp/vlc_frame_completed.txt
echo "Snapshot location: ${FOUND_SNAPSHOT:-none}" >> /tmp/vlc_frame_completed.txt

# Create summary
cat > /tmp/vlc_frame_summary.txt <<EOF
Task: Frame Analysis Export
Timestamp: $(date)
Expected snapshot: $EXPECTED_SNAPSHOT
Snapshot found: $([ -n "$FOUND_SNAPSHOT" ] && echo "YES" || echo "NO")
Snapshot location: ${FOUND_SNAPSHOT:-none}
EOF

echo "=== Export Complete ==="
cat /tmp/vlc_frame_summary.txt