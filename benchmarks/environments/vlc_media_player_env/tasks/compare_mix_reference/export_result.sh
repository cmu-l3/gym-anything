#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Mix Reference Result ==="

# Check for playlist file
PLAYLIST_DIR="/home/ga/Music/playlists"
EXPECTED_PLAYLIST="$PLAYLIST_DIR/mix_comparison.xspf"

if [ -f "$EXPECTED_PLAYLIST" ]; then
    echo "✅ Playlist found: $EXPECTED_PLAYLIST"
    cp "$EXPECTED_PLAYLIST" /tmp/vlc_mix_comparison_playlist.xspf
    echo "Playlist contents:"
    cat "$EXPECTED_PLAYLIST"
else
    echo "⚠️ Expected playlist not found at: $EXPECTED_PLAYLIST"
    
    # Look for any recently created XSPF playlist in the directory
    RECENT_PLAYLIST=$(find "$PLAYLIST_DIR" -name "*.xspf" -mmin -10 -type f 2>/dev/null | head -1)
    
    if [ -n "$RECENT_PLAYLIST" ]; then
        echo "Found recent playlist: $RECENT_PLAYLIST"
        cp "$RECENT_PLAYLIST" /tmp/vlc_mix_comparison_playlist.xspf
    else
        # Check other common locations
        for alt_location in "/home/ga/Videos/playlists" "/home/ga/Documents" "/home/ga"; do
            ALT_PLAYLIST=$(find "$alt_location" -name "*mix*comparison*.xspf" -o -name "*comparison*.xspf" -mmin -10 -type f 2>/dev/null | head -1)
            if [ -n "$ALT_PLAYLIST" ]; then
                echo "Found playlist in alternate location: $ALT_PLAYLIST"
                cp "$ALT_PLAYLIST" /tmp/vlc_mix_comparison_playlist.xspf
                break
            fi
        done
    fi
fi

# Copy audio files for verification that they exist and are accessible
if [ -f /home/ga/Music/my_mix.mp3 ]; then
    cp /home/ga/Music/my_mix.mp3 /tmp/vlc_my_mix.mp3
    echo "✅ Copied my_mix.mp3"
fi

if [ -f /home/ga/Music/reference_track.mp3 ]; then
    cp /home/ga/Music/reference_track.mp3 /tmp/vlc_reference_track.mp3
    echo "✅ Copied reference_track.mp3"
fi

# Close VLC
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

echo "$(date)" > /tmp/vlc_mix_compare_completed.txt
echo "Mix comparison playlist task completed" >> /tmp/vlc_mix_compare_completed.txt

echo "=== Export Complete ==="