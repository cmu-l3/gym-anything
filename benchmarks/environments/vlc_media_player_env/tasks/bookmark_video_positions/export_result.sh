#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bookmark Video Positions Result ==="

EXPORT_DIR="/tmp/task_export"
mkdir -p "$EXPORT_DIR"

# Track what we find
FOUND_FILES=0

# Export VLC media library (primary bookmark storage)
if [ -f /home/ga/.local/share/vlc/ml.xspf ]; then
    cp /home/ga/.local/share/vlc/ml.xspf "$EXPORT_DIR/ml.xspf"
    echo "✓ Exported media library: ml.xspf"
    FOUND_FILES=$((FOUND_FILES + 1))
fi

# Export any playlist files from playlists directory
if [ -d /home/ga/Videos/playlists ]; then
    PLAYLISTS=$(find /home/ga/Videos/playlists -type f \( -name "*.m3u" -o -name "*.m3u8" -o -name "*.xspf" \) 2>/dev/null)
    
    for playlist in $PLAYLISTS; do
        BASENAME=$(basename "$playlist")
        cp "$playlist" "$EXPORT_DIR/$BASENAME"
        echo "✓ Exported playlist: $BASENAME"
        FOUND_FILES=$((FOUND_FILES + 1))
    done
fi

# Export any playlist files from bookmarks directory
if [ -d /home/ga/Videos/bookmarks ]; then
    BOOKMARKS=$(find /home/ga/Videos/bookmarks -type f \( -name "*.m3u" -o -name "*.m3u8" -o -name "*.xspf" -o -name "*.txt" \) 2>/dev/null)
    
    for bookmark in $BOOKMARKS; do
        BASENAME=$(basename "$bookmark")
        cp "$bookmark" "$EXPORT_DIR/bookmark_$BASENAME"
        echo "✓ Exported bookmark file: $BASENAME"
        FOUND_FILES=$((FOUND_FILES + 1))
    done
fi

# Export VLC config files that might contain bookmark data
if [ -f /home/ga/.config/vlc/vlcrc ]; then
    cp /home/ga/.config/vlc/vlcrc "$EXPORT_DIR/vlcrc"
    echo "✓ Exported vlcrc config"
fi

if [ -f /home/ga/.config/vlc/vlc-qt-interface.conf ]; then
    cp /home/ga/.config/vlc/vlc-qt-interface.conf "$EXPORT_DIR/vlc-qt-interface.conf"
    echo "✓ Exported Qt interface config"
fi

# Look for any recently created XSPF files in VLC's local share
if [ -d /home/ga/.local/share/vlc ]; then
    RECENT_XSPF=$(find /home/ga/.local/share/vlc -name "*.xspf" -mmin -15 2>/dev/null)
    
    for xspf in $RECENT_XSPF; do
        BASENAME=$(basename "$xspf")
        if [ "$BASENAME" != "ml.xspf" ]; then
            cp "$xspf" "$EXPORT_DIR/vlc_$BASENAME"
            echo "✓ Exported VLC file: $BASENAME"
            FOUND_FILES=$((FOUND_FILES + 1))
        fi
    done
fi

# Check home directory for any bookmark-related files created by user
RECENT_BOOKMARKS=$(find /home/ga -maxdepth 3 -type f \
    \( -name "*bookmark*" -o -name "*documentary*" \) \
    \( -name "*.m3u" -o -name "*.xspf" -o -name "*.txt" \) \
    -mmin -15 2>/dev/null | head -5)

for file in $RECENT_BOOKMARKS; do
    BASENAME=$(basename "$file")
    if [ ! -f "$EXPORT_DIR/$BASENAME" ]; then
        cp "$file" "$EXPORT_DIR/user_$BASENAME"
        echo "✓ Exported user file: $BASENAME"
        FOUND_FILES=$((FOUND_FILES + 1))
    fi
done

# Create a summary file
cat > "$EXPORT_DIR/export_summary.txt" << EOF
Bookmark Export Summary
Date: $(date)
Files found: $FOUND_FILES

Expected bookmarks:
- Resume Point: 35:20 (2120s)
- Mars Landing: 12:30 (750s)
- Voyager Mission: 58:00 (3480s)
- Conclusion: 82:15 (4935s)
EOF

# Close VLC if still running
if is_vlc_running; then
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
fi

# Wait a moment for files to flush
sleep 1

# Final check and list exported files
echo ""
echo "=== Exported Files ==="
ls -lh "$EXPORT_DIR/"
echo ""

if [ $FOUND_FILES -eq 0 ]; then
    echo "⚠️ WARNING: No bookmark files found!"
    echo "   User may not have created/saved bookmarks"
else
    echo "✓ Found $FOUND_FILES bookmark-related file(s)"
fi

echo "$(date)" > /tmp/vlc_bookmark_completed.txt
echo "Files found: $FOUND_FILES" >> /tmp/vlc_bookmark_completed.txt

echo "=== Export Complete ==="