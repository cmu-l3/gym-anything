#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Backup VLC Preferences Result ==="

BACKUP_DIR="/home/ga/Documents/vlc_backup"
EXPORT_DIR="/tmp/vlc_backup_result"

# Clean any previous export
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

# Check if backup directory was created
if [ -d "$BACKUP_DIR" ]; then
    echo "✅ Backup directory found: $BACKUP_DIR"
    
    # List contents
    echo "Backup directory contents:"
    ls -lah "$BACKUP_DIR" || true
    
    # Copy entire backup to export location for verification
    cp -r "$BACKUP_DIR" "$EXPORT_DIR/" || {
        echo "⚠️ Failed to copy backup directory"
    }
    
    # Count backed up files
    FILE_COUNT=$(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)
    echo "Backed up files count: $FILE_COUNT"
    
    # Check for specific essential files
    if [ -f "$BACKUP_DIR/vlcrc" ]; then
        echo "✅ vlcrc backed up"
        cp "$BACKUP_DIR/vlcrc" "$EXPORT_DIR/backed_up_vlcrc" 2>/dev/null || true
    else
        echo "⚠️ vlcrc NOT found in backup"
    fi
    
    if [ -f "$BACKUP_DIR/vlc-qt-interface.conf" ]; then
        echo "✅ vlc-qt-interface.conf backed up"
        cp "$BACKUP_DIR/vlc-qt-interface.conf" "$EXPORT_DIR/backed_up_vlc-qt-interface.conf" 2>/dev/null || true
    else
        echo "⚠️ vlc-qt-interface.conf NOT found in backup"
    fi
    
else
    echo "❌ Backup directory not found at: $BACKUP_DIR"
    echo "The agent did not create the backup directory."
fi

# Also export original config for comparison
ORIGINAL_DIR="/home/ga/.config/vlc"
if [ -d "$ORIGINAL_DIR" ]; then
    mkdir -p "$EXPORT_DIR/original"
    cp "$ORIGINAL_DIR/vlcrc" "$EXPORT_DIR/original/vlcrc" 2>/dev/null || true
    cp "$ORIGINAL_DIR/vlc-qt-interface.conf" "$EXPORT_DIR/original/vlc-qt-interface.conf" 2>/dev/null || true
    echo "Original config also exported for verification"
fi

# Create summary JSON
cat > "$EXPORT_DIR/backup_summary.json" << EOF
{
    "backup_directory_exists": $([ -d "$BACKUP_DIR" ] && echo "true" || echo "false"),
    "file_count": $(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l || echo 0),
    "vlcrc_backed_up": $([ -f "$BACKUP_DIR/vlcrc" ] && echo "true" || echo "false"),
    "vlc_qt_conf_backed_up": $([ -f "$BACKUP_DIR/vlc-qt-interface.conf" ] && echo "true" || echo "false"),
    "timestamp": "$(date -Iseconds)"
}
EOF

cat "$EXPORT_DIR/backup_summary.json"

# Close VLC if running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    kill_vlc ga || true
fi

# Create completion marker
echo "$(date -Iseconds)" > /tmp/vlc_backup_completed.txt
echo "Backup task export completed" >> /tmp/vlc_backup_completed.txt

echo ""
echo "=== Export Complete ==="
echo "Results exported to: $EXPORT_DIR"