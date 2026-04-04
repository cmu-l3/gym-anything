#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Playlist Result ==="

# Check for playlist file
PLAYLIST_DIR="/home/ga/Videos/playlists"
EXPECTED_PLAYLIST="$PLAYLIST_DIR/my_playlist.m3u"

if [ -f "$EXPECTED_PLAYLIST" ]; then
    echo "✅ Playlist found: $EXPECTED_PLAYLIST"
    cp "$EXPECTED_PLAYLIST" /tmp/vlc_created_playlist.m3u
    cat "$EXPECTED_PLAYLIST"
else
    echo "⚠️ Expected playlist not found"
    
    # Look for any recently created playlist
    RECENT_PLAYLIST=$(find "$PLAYLIST_DIR" -name "*.m3u" -o -name "*.xspf" -mmin -5 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "Found recent playlist: $RECENT_PLAYLIST"
        cp "$RECENT_PLAYLIST" /tmp/vlc_created_playlist.m3u
    fi
fi

# Close VLC
if is_vlc_running; then
    safe_xdotool ga :1 key ctrl+q
    sleep 1
fi

echo "$(date)" > /tmp/vlc_playlist_completed.txt

echo "=== Export Complete ==="
