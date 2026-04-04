#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Batch Media Catalog Result ==="

# Close any running VLC instances
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Kill any remaining VLC processes
kill_vlc ga || true
sleep 1

# Copy catalog report if it exists
REPORT_PATH="/home/ga/Documents/media_catalog.txt"
if [ -f "$REPORT_PATH" ]; then
    echo "✅ Catalog report found"
    cp "$REPORT_PATH" /tmp/batch_catalog_report.txt
    echo "Report content:"
    cat "$REPORT_PATH"
else
    echo "⚠️ Catalog report not found at $REPORT_PATH"
    # Check for any text files in Documents
    RECENT_TXT=$(find /home/ga/Documents -name "*.txt" -type f -mmin -10 2>/dev/null | head -1)
    if [ -n "$RECENT_TXT" ]; then
        echo "Found recent text file: $RECENT_TXT"
        cp "$RECENT_TXT" /tmp/batch_catalog_report.txt
    fi
fi

# Copy all snapshots if directory exists
SNAPSHOT_DIR="/home/ga/Pictures/catalog_snapshots"
if [ -d "$SNAPSHOT_DIR" ]; then
    echo "✅ Snapshot directory found"
    mkdir -p /tmp/batch_catalog_snapshots
    cp -r "$SNAPSHOT_DIR"/* /tmp/batch_catalog_snapshots/ 2>/dev/null || true
    
    SNAPSHOT_COUNT=$(ls /tmp/batch_catalog_snapshots/*.png 2>/dev/null | wc -l)
    echo "Found $SNAPSHOT_COUNT snapshot(s)"
    ls -lh /tmp/batch_catalog_snapshots/ 2>/dev/null || true
else
    echo "⚠️ Snapshot directory not found"
    # Check if snapshots were saved elsewhere (e.g., VLC's default location)
    VLC_SNAPSHOT_DIR="/home/ga/Pictures/vlc"
    if [ -d "$VLC_SNAPSHOT_DIR" ]; then
        mkdir -p /tmp/batch_catalog_snapshots
        # Copy recent snapshots (last 10 minutes)
        find "$VLC_SNAPSHOT_DIR" -name "*.png" -mmin -10 -exec cp {} /tmp/batch_catalog_snapshots/ \; 2>/dev/null || true
        SNAPSHOT_COUNT=$(ls /tmp/batch_catalog_snapshots/*.png 2>/dev/null | wc -l)
        echo "Found $SNAPSHOT_COUNT snapshot(s) in VLC default directory"
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/batch_catalog_completed.txt
echo "Batch media catalog task completed" >> /tmp/batch_catalog_completed.txt

echo "=== Export Complete ==="