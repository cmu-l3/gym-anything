#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bookmark Study Scenes Result ==="

# Try to query bookmarks via VLC if it's still running
BOOKMARKS_INFO="{}"
BOOKMARK_COUNT=0
RUNTIME_CAPTURED="false"

if is_vlc_running; then
    echo "VLC is running, attempting to query bookmarks..."
    
    # Note: VLC RC interface doesn't have direct bookmark query commands
    # Bookmarks are stored in the media library, so we'll rely on file-based verification
    
    echo "Bookmarks will be verified from VLC storage files"
fi

# Close VLC gracefully to ensure bookmarks are saved
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to save bookmarks..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3  # Give VLC time to save bookmarks
fi

# Wait for VLC to fully close and save data
sleep 2

# Check for bookmark storage files
echo "Checking for bookmark storage files..."

# VLC stores bookmarks in media library
ML_XSPF="/home/ga/.local/share/vlc/ml.xspf"
ML_DB="/home/ga/.local/share/vlc/ml.db"
BOOKMARKS_XSPF="/home/ga/.config/vlc/bookmarks.xspf"

BOOKMARK_FILES_FOUND="false"

if [ -f "$ML_XSPF" ]; then
    echo "✅ Found media library XSPF: $ML_XSPF"
    cp "$ML_XSPF" /tmp/vlc_ml.xspf
    BOOKMARK_FILES_FOUND="true"
    
    # Try to extract bookmark count from XSPF
    if grep -q "bookmarks=" "$ML_XSPF"; then
        # Count bookmark entries (rough estimate)
        BOOKMARK_COUNT=$(grep -o "name=" "$ML_XSPF" | wc -l)
        echo "Estimated bookmarks from XSPF: $BOOKMARK_COUNT"
    fi
else
    echo "⚠️ Media library XSPF not found: $ML_XSPF"
fi

if [ -f "$ML_DB" ]; then
    echo "✅ Found media library DB: $ML_DB"
    cp "$ML_DB" /tmp/vlc_ml.db
    BOOKMARK_FILES_FOUND="true"
else
    echo "⚠️ Media library DB not found: $ML_DB"
fi

if [ -f "$BOOKMARKS_XSPF" ]; then
    echo "✅ Found bookmarks XSPF: $BOOKMARKS_XSPF"
    cp "$BOOKMARKS_XSPF" /tmp/vlc_bookmarks.xspf
    BOOKMARK_FILES_FOUND="true"
else
    echo "⚠️ Bookmarks XSPF not found: $BOOKMARKS_XSPF"
fi

# Also check alternate locations
ALT_ML="/home/ga/.local/share/vlc/MediaLibrary"
if [ -d "$ALT_ML" ]; then
    echo "Found media library directory: $ALT_ML"
    find "$ALT_ML" -type f -exec cp {} /tmp/ \; 2>/dev/null || true
fi

# Write summary JSON
cat > /tmp/vlc_bookmarks_result.json <<EOF
{
    "bookmark_count_estimate": $BOOKMARK_COUNT,
    "files_found": "$BOOKMARK_FILES_FOUND",
    "ml_xspf_exists": $([ -f "$ML_XSPF" ] && echo "true" || echo "false"),
    "ml_db_exists": $([ -f "$ML_DB" ] && echo "true" || echo "false"),
    "bookmarks_xspf_exists": $([ -f "$BOOKMARKS_XSPF" ] && echo "true" || echo "false"),
    "video_duration": 1500
}
EOF

echo "✅ Bookmarks result saved to /tmp/vlc_bookmarks_result.json"
cat /tmp/vlc_bookmarks_result.json

echo "$(date)" > /tmp/vlc_bookmarks_completed.txt
echo "Bookmark study scenes task completed" >> /tmp/vlc_bookmarks_completed.txt
echo "Bookmark files found: $BOOKMARK_FILES_FOUND" >> /tmp/vlc_bookmarks_completed.txt

# List all files in /tmp for debugging
echo "Files exported to /tmp:"
ls -lh /tmp/vlc_* 2>/dev/null || echo "No VLC files found"

echo "=== Export Complete ==="