#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Batch Video Library Verification Result ==="

# Define paths
PLAYLIST_FILE="/home/ga/Videos/playlists/verified_archive.m3u"
PLAYLIST_DIR="/home/ga/Videos/playlists"
ARCHIVE_DIR="/home/ga/Videos/archive_check"

# Check for expected playlist file
if [ -f "$PLAYLIST_FILE" ]; then
    echo "✅ Playlist found at expected location: $PLAYLIST_FILE"
    cp "$PLAYLIST_FILE" /tmp/vlc_batch_verify_playlist.m3u
    
    echo "Playlist contents:"
    cat "$PLAYLIST_FILE"
    
    # Get file info
    FILE_SIZE=$(stat -f%z "$PLAYLIST_FILE" 2>/dev/null || stat -c%s "$PLAYLIST_FILE" 2>/dev/null || echo "0")
    echo "Playlist size: $FILE_SIZE bytes"
else
    echo "⚠️ Expected playlist not found at: $PLAYLIST_FILE"
    
    # Look for any recently created M3U or XSPF playlist in the directory
    echo "Searching for recently created playlists..."
    RECENT_PLAYLIST=$(find "$PLAYLIST_DIR" -type f \( -name "*.m3u" -o -name "*.m3u8" -o -name "*.xspf" \) -mmin -5 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "Found recent playlist: $RECENT_PLAYLIST"
        cp "$RECENT_PLAYLIST" /tmp/vlc_batch_verify_playlist.m3u
        cat "$RECENT_PLAYLIST"
    else
        echo "❌ No recent playlist files found"
        # Create empty file to avoid errors in verifier
        touch /tmp/vlc_batch_verify_playlist.m3u
    fi
fi

# Export metadata for verification
cat > /tmp/vlc_batch_verify_metadata.json <<EOF
{
  "task_id": "batch_verify_library@1",
  "playlist_path": "$PLAYLIST_FILE",
  "playlist_exists": $([ -f "$PLAYLIST_FILE" ] && echo "true" || echo "false"),
  "archive_directory": "$ARCHIVE_DIR",
  "expected_file_count": 5,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Metadata saved to /tmp/vlc_batch_verify_metadata.json"
cat /tmp/vlc_batch_verify_metadata.json

# List archive contents for reference
echo ""
echo "Archive directory contents:"
ls -lh "$ARCHIVE_DIR" > /tmp/vlc_batch_verify_archive.txt 2>&1
cat /tmp/vlc_batch_verify_archive.txt

# Close VLC gracefully
if is_vlc_running; then
    echo ""
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "VLC still running, force killing..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_batch_verify_completed.txt
echo "Batch verification task completed" >> /tmp/vlc_batch_verify_completed.txt

echo ""
echo "=== Export Complete ==="
echo "Results exported to:"
echo "  - /tmp/vlc_batch_verify_playlist.m3u"
echo "  - /tmp/vlc_batch_verify_metadata.json"
echo "  - /tmp/vlc_batch_verify_archive.txt"
echo "  - /tmp/vlc_batch_verify_completed.txt"