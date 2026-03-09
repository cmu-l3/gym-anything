#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure ASL Practice Result ==="

# First, ensure VLC is closed to force config save
if is_vlc_running; then
    echo "VLC is running, closing to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3
fi

# Export VLC configuration file
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" /tmp/vlc_asl_config.txt
    echo "✓ Exported VLC config: $VLC_RC"
    
    # Log relevant settings for debugging
    echo "=== Key Settings ==="
    grep -E "(rate|speed|key-frame|loop|bookmark)" "$VLC_RC" || echo "No matching settings found"
else
    echo "⚠ VLC config not found at $VLC_RC"
    touch /tmp/vlc_asl_config.txt
fi

# Check for bookmark/playlist files in various locations
BOOKMARK_FOUND="false"
BOOKMARK_FILES=""

# Check for XSPF playlists
for path in \
    "/home/ga/.config/vlc/bookmarks.xspf" \
    "/home/ga/.local/share/vlc/ml.xspf" \
    "/home/ga/.local/share/vlc/playlist.xspf" \
    "/home/ga/Videos/asl_bookmarks.xspf" \
    "/home/ga/Videos/asl_bookmarks.m3u" \
    "/home/ga/Videos/asl_tutorial_bookmarks.xspf" \
    "/home/ga/Videos/practice_signs.xspf" \
    "/home/ga/Videos/playlists/asl_bookmarks.xspf" \
    "/home/ga/Videos/playlists/asl_bookmarks.m3u"
do
    if [ -f "$path" ]; then
        echo "✓ Found bookmark file: $path"
        cp "$path" "/tmp/vlc_asl_bookmarks_$(basename $path)"
        BOOKMARK_FOUND="true"
        BOOKMARK_FILES="${BOOKMARK_FILES}${path};"
    fi
done

# Also check for any recently modified playlist files
RECENT_PLAYLISTS=$(find /home/ga/.config/vlc /home/ga/.local/share/vlc /home/ga/Videos -type f \( -name "*.xspf" -o -name "*.m3u" \) -mmin -10 2>/dev/null || true)
if [ -n "$RECENT_PLAYLISTS" ]; then
    echo "Recent playlist files found:"
    echo "$RECENT_PLAYLISTS"
    for file in $RECENT_PLAYLISTS; do
        if [ -f "$file" ]; then
            cp "$file" "/tmp/vlc_asl_recent_$(basename $file)" || true
        fi
    done
fi

# Create summary JSON with findings
cat > /tmp/vlc_asl_export_summary.json <<EOF
{
    "config_exported": $([ -f "$VLC_RC" ] && echo "true" || echo "false"),
    "bookmarks_found": $BOOKMARK_FOUND,
    "bookmark_files": "$BOOKMARK_FILES",
    "export_time": "$(date -Iseconds)"
}
EOF

echo "✓ Export summary saved"
cat /tmp/vlc_asl_export_summary.json

# Create completion marker
echo "$(date)" > /tmp/vlc_asl_completed.txt
echo "ASL practice configuration task completed" >> /tmp/vlc_asl_completed.txt

echo "=== Export Complete ==="
echo ""
echo "Exported files:"
echo "  - /tmp/vlc_asl_config.txt (VLC config)"
echo "  - /tmp/vlc_asl_bookmarks_* (if found)"
echo "  - /tmp/vlc_asl_export_summary.json"
echo "  - /tmp/vlc_asl_completed.txt"