#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting DJ Setlist Curation Result ==="

# Expected playlist location
PLAYLIST_PATH="/home/ga/Music/playlists/approved_setlist.xspf"
RESULT_DIR="/tmp/task_result"
METADATA_DIR="/tmp/dj_task_metadata"

mkdir -p "$RESULT_DIR"
mkdir -p "$RESULT_DIR/track_info"

# Check if expected playlist exists
if [ -f "$PLAYLIST_PATH" ]; then
    echo "✅ Playlist found at expected location: $PLAYLIST_PATH"
    cp "$PLAYLIST_PATH" "$RESULT_DIR/approved_setlist.xspf"
    echo "Playlist contents:"
    cat "$PLAYLIST_PATH"
else
    echo "⚠️ Expected playlist not found at $PLAYLIST_PATH"
    
    # Look for any recently created playlist in the playlists directory
    RECENT_PLAYLIST=$(find /home/ga/Music/playlists -name "*.xspf" -o -name "*.m3u" -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "Found recent playlist: $RECENT_PLAYLIST"
        cp "$RECENT_PLAYLIST" "$RESULT_DIR/approved_setlist.xspf"
    else
        echo "❌ No playlist file found"
    fi
fi

# Export track metadata for verification
echo "Exporting track metadata..."
TRACKS_DIR="/home/ga/Music/wedding_requests"

for track in "$TRACKS_DIR"/*; do
    if [ -f "$track" ]; then
        basename "$track" >> "$RESULT_DIR/track_info/track_list.txt"
        
        # Get bitrate using ffprobe
        if command -v ffprobe &> /dev/null; then
            ffprobe -v error -select_streams a:0 \
                -show_entries stream=codec_name,bit_rate,sample_rate,codec_type \
                -show_entries format=format_name \
                -of json "$track" > "$RESULT_DIR/track_info/$(basename "$track").json" 2>&1 || {
                echo "Error probing $track" > "$RESULT_DIR/track_info/$(basename "$track").json"
            }
        fi
    fi
done

# Also copy ground truth bitrate metadata
if [ -d "$METADATA_DIR" ]; then
    cp -r "$METADATA_DIR" "$RESULT_DIR/ground_truth_bitrates"
fi

echo "Track metadata exported to $RESULT_DIR/track_info/"

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

# Create completion marker
echo "$(date)" > "$RESULT_DIR/dj_setlist_completed.txt"
echo "DJ setlist curation task completed" >> "$RESULT_DIR/dj_setlist_completed.txt"

echo "✅ Export complete"
echo "Results saved to: $RESULT_DIR"