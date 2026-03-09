#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verify Restored Media Result ==="

# Give VLC a moment to finalize any writes
sleep 1

# Close VLC to ensure history is written to disk
if is_vlc_running; then
    echo "Closing VLC to save history..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Export VLC history files
echo "Exporting VLC history..."
VLC_DATA_DIR="/home/ga/.local/share/vlc"
VLC_CONFIG_DIR="/home/ga/.config/vlc"

# Copy media library XSPF (contains recently played)
if [ -f "$VLC_DATA_DIR/ml.xspf" ]; then
    cp "$VLC_DATA_DIR/ml.xspf" /tmp/vlc_history_ml.xspf
    echo "✅ Copied ml.xspf"
else
    echo "⚠️ ml.xspf not found"
    touch /tmp/vlc_history_ml.xspf  # Create empty file
fi

# Copy VLC Qt interface config (contains recent MRL list)
if [ -f "$VLC_CONFIG_DIR/vlc-qt-interface.conf" ]; then
    cp "$VLC_CONFIG_DIR/vlc-qt-interface.conf" /tmp/vlc_history_qt.conf
    echo "✅ Copied vlc-qt-interface.conf"
else
    echo "⚠️ vlc-qt-interface.conf not found"
    touch /tmp/vlc_history_qt.conf
fi

# Also check for recently-used file (GTK)
if [ -f "/home/ga/.local/share/recently-used.xbel" ]; then
    cp "/home/ga/.local/share/recently-used.xbel" /tmp/vlc_recently_used.xbel
    echo "✅ Copied recently-used.xbel"
else
    touch /tmp/vlc_recently_used.xbel
fi

# Copy the expected file list created during setup
if [ -f "/tmp/backup_media_list.txt" ]; then
    cp /tmp/backup_media_list.txt /tmp/backup_media_expected.txt
    echo "✅ Copied expected media list"
else
    # Fallback: regenerate list
    find /home/ga/Videos/restored_backup -type f \( -name "*.mp4" -o -name "*.mp3" -o -name "*.avi" -o -name "*.mkv" \) > /tmp/backup_media_expected.txt
fi

# Create a comprehensive summary of files in backup directory
echo "Creating backup directory summary..."
BACKUP_DIR="/home/ga/Videos/restored_backup"
cat > /tmp/backup_directory_info.json <<EOF
{
    "backup_directory": "$BACKUP_DIR",
    "files": [
EOF

# List all media files with metadata
first=true
for file in "$BACKUP_DIR"/*.{mp4,mp3,avi,mkv,flv,mov} 2>/dev/null; do
    if [ -f "$file" ]; then
        if [ "$first" = false ]; then
            echo "," >> /tmp/backup_directory_info.json
        fi
        first=false
        
        filename=$(basename "$file")
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        
        cat >> /tmp/backup_directory_info.json <<FILEEOF
        {
            "name": "$filename",
            "path": "$file",
            "size": $size
        }
FILEEOF
    fi
done

cat >> /tmp/backup_directory_info.json <<EOF

    ]
}
EOF

echo "✅ Backup directory info saved"
cat /tmp/backup_directory_info.json

# Create completion marker
echo "$(date)" > /tmp/vlc_verify_backup_completed.txt
echo "Verification task completed" >> /tmp/vlc_verify_backup_completed.txt

echo "=== Export Complete ==="