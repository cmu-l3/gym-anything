#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Presentation Clips Result ==="

OUTPUT_DIR="/home/ga/Documents/presentation"
EXPECTED_PLAYLIST="$OUTPUT_DIR/talk_clips.xspf"

# Check for playlist file at expected location
if [ -f "$EXPECTED_PLAYLIST" ]; then
    echo "✅ Playlist found at expected location: $EXPECTED_PLAYLIST"
    cp "$EXPECTED_PLAYLIST" /tmp/vlc_presentation_playlist.xspf
    
    # Show file info
    size=$(stat -c%s "$EXPECTED_PLAYLIST" 2>/dev/null || stat -f%z "$EXPECTED_PLAYLIST" 2>/dev/null)
    echo "   Playlist size: $((size / 1024)) KB"
    
    # Show first few lines for debugging
    echo "   Playlist preview:"
    head -20 "$EXPECTED_PLAYLIST" | sed 's/^/   /'
else
    echo "⚠️ Playlist not found at expected location: $EXPECTED_PLAYLIST"
    
    # Look for any XSPF playlists created recently in the output directory
    RECENT_PLAYLIST=$(find "$OUTPUT_DIR" -name "*.xspf" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "   Found recent XSPF playlist: $RECENT_PLAYLIST"
        cp "$RECENT_PLAYLIST" /tmp/vlc_presentation_playlist.xspf
    else
        # Check if any playlist exists in common locations
        for dir in "$OUTPUT_DIR" /home/ga/Videos /home/ga/Documents; do
            FALLBACK=$(find "$dir" -name "*.xspf" -type f -mmin -10 2>/dev/null | head -1)
            if [ -n "$FALLBACK" ]; then
                echo "   Found playlist in $dir: $FALLBACK"
                cp "$FALLBACK" /tmp/vlc_presentation_playlist.xspf
                break
            fi
        done
    fi
fi

# Close VLC
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Export VLC logs if available
if [ -f "/tmp/vlc_presentation_task.log" ]; then
    cp "/tmp/vlc_presentation_task.log" /tmp/vlc_presentation_task_export.log
fi

# Create completion marker
echo "$(date -u)" > /tmp/vlc_presentation_completed.txt
echo "Task: prepare_presentation_clips@1" >> /tmp/vlc_presentation_completed.txt

if [ -f "/tmp/vlc_presentation_playlist.xspf" ]; then
    echo "Status: Playlist exported successfully" >> /tmp/vlc_presentation_completed.txt
else
    echo "Status: Playlist not found" >> /tmp/vlc_presentation_completed.txt
fi

echo "=== Export Complete ==="