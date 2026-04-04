#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Practice Segment Playlist Result ==="

# Define expected playlist location and alternatives
PLAYLIST_DIR="/home/ga/Videos/playlists"
EXPECTED_PLAYLIST="$PLAYLIST_DIR/practice_sequence"

PLAYLIST_FOUND=""
PLAYLIST_FORMAT=""

# Check for playlist file with various extensions
for ext in .xspf .m3u8 .m3u; do
    if [ -f "${EXPECTED_PLAYLIST}${ext}" ]; then
        PLAYLIST_FOUND="${EXPECTED_PLAYLIST}${ext}"
        PLAYLIST_FORMAT="${ext}"
        echo "✅ Found playlist: $PLAYLIST_FOUND"
        break
    fi
done

# If not found at expected location, search for any recent playlist
if [ -z "$PLAYLIST_FOUND" ]; then
    echo "⚠️ Expected playlist not found, searching for alternatives..."
    
    # Look for any recently created playlist files (within last 15 minutes)
    RECENT_PLAYLIST=$(find "$PLAYLIST_DIR" -type f \( -name "*.m3u" -o -name "*.m3u8" -o -name "*.xspf" \) -mmin -15 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        PLAYLIST_FOUND="$RECENT_PLAYLIST"
        PLAYLIST_FORMAT=$(echo "$RECENT_PLAYLIST" | grep -oP '\.(m3u8?|xspf)$')
        echo "Found recent playlist: $PLAYLIST_FOUND"
    fi
fi

# Copy playlist to /tmp for verification
if [ -n "$PLAYLIST_FOUND" ]; then
    cp "$PLAYLIST_FOUND" /tmp/vlc_practice_playlist.txt
    echo "Playlist contents:"
    echo "---"
    cat "$PLAYLIST_FOUND"
    echo "---"
    
    # Create metadata file
    cat > /tmp/vlc_practice_playlist_meta.json <<EOF
{
    "found": true,
    "path": "$PLAYLIST_FOUND",
    "format": "$PLAYLIST_FORMAT",
    "size_bytes": $(stat -c%s "$PLAYLIST_FOUND" 2>/dev/null || echo 0)
}
EOF
else
    echo "❌ No playlist file found"
    
    # Create empty metadata to indicate failure
    cat > /tmp/vlc_practice_playlist_meta.json <<EOF
{
    "found": false,
    "path": "",
    "format": "",
    "size_bytes": 0
}
EOF
    
    # Create empty placeholder
    touch /tmp/vlc_practice_playlist.txt
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

# Create completion marker
echo "$(date)" > /tmp/vlc_practice_playlist_completed.txt
echo "Playlist task completed" >> /tmp/vlc_practice_playlist_completed.txt
if [ -n "$PLAYLIST_FOUND" ]; then
    echo "Playlist found: $PLAYLIST_FOUND" >> /tmp/vlc_practice_playlist_completed.txt
fi

echo "=== Export Complete ==="