#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Generate Preview Contact Sheet Result ==="

OUTPUT_DIR="/home/ga/Pictures/contact_sheets"

# Check if output directory exists
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "⚠️ Output directory not found: $OUTPUT_DIR"
    mkdir -p /tmp/contact_sheets_export
    echo "No snapshots found" > /tmp/contact_sheets_export/no_output.txt
else
    # List all files in output directory
    echo "Checking for snapshots in $OUTPUT_DIR..."
    SNAPSHOT_COUNT=$(find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.jpg" \) 2>/dev/null | wc -l)
    
    echo "Found $SNAPSHOT_COUNT snapshot files"
    
    if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
        # Create temp directory for exports
        mkdir -p /tmp/contact_sheets_export
        
        # Copy all snapshots to export directory
        echo "Copying snapshots to /tmp/contact_sheets_export/..."
        find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.jpg" \) -exec cp {} /tmp/contact_sheets_export/ \;
        
        # List what was copied
        ls -lh /tmp/contact_sheets_export/
        
        echo "✅ Copied $SNAPSHOT_COUNT snapshots"
    else
        echo "⚠️ No snapshot files found in output directory"
        mkdir -p /tmp/contact_sheets_export
        echo "No snapshots created" > /tmp/contact_sheets_export/no_output.txt
    fi
fi

# Create completion marker with metadata
cat > /tmp/contact_sheet_completed.txt <<EOF
$(date)
Task: Generate Preview Contact Sheet
Output directory: $OUTPUT_DIR
Snapshots found: $SNAPSHOT_COUNT
EOF

# Close VLC if running
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
        kill_vlc ga
    fi
fi

echo "=== Export Complete ==="