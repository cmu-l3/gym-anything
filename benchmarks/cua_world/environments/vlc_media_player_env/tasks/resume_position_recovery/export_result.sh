#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

OUTPUT_DIR="${GA_OUTPUT_DIR:-/tmp/outputs}"
mkdir -p "$OUTPUT_DIR"

echo "=== Exporting Resume Position Recovery Verification Data ==="

# Wait a moment to ensure VLC has written any pending data
sleep 2

# Export VLC configuration
echo "Exporting VLC preferences..."
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "$OUTPUT_DIR/vlcrc"
    echo "✓ Copied vlcrc"
    
    # Extract key settings for logging
    QT_CONTINUE=$(grep "^qt-continue=" "$VLC_RC" | cut -d= -f2 || echo "NOT_SET")
    echo "  qt-continue setting: $QT_CONTINUE"
else
    echo "⚠️ vlcrc not found"
    echo "NOT_FOUND" > "$OUTPUT_DIR/vlcrc"
fi

# Export VLC's recent media database (XSPF format - contains playback positions)
echo "Exporting recent media database..."
ML_XSPF="/home/ga/.local/share/vlc/ml.xspf"
if [ -f "$ML_XSPF" ]; then
    cp "$ML_XSPF" "$OUTPUT_DIR/ml.xspf"
    echo "✓ Copied ml.xspf (media library)"
    
    # Log number of media entries
    ENTRY_COUNT=$(grep -c "<track>" "$ML_XSPF" 2>/dev/null || echo "0")
    echo "  Media entries: $ENTRY_COUNT"
else
    echo "⚠️ ml.xspf not found"
    echo "NOT_FOUND" > "$OUTPUT_DIR/ml.xspf"
fi

# Export SQLite media library database (VLC 3.x uses this)
ML_DB="/home/ga/.local/share/vlc/vlc-media-library.db"
if [ -f "$ML_DB" ]; then
    cp "$ML_DB" "$OUTPUT_DIR/vlc-media-library.db"
    echo "✓ Copied media library database"
    
    # Try to extract playback info using sqlite3
    if command -v sqlite3 &> /dev/null; then
        echo "  Querying database..."
        sqlite3 "$ML_DB" "SELECT mrl, progress, duration, play_count FROM Media WHERE mrl LIKE '%documentary_urban_planning%';" 2>/dev/null | head -5 || echo "  (No entries found or query failed)"
    fi
else
    echo "⚠️ Media library database not found"
fi

# Export VLC state files from cache (may contain additional playback info)
CACHE_DIR="/home/ga/.cache/vlc"
if [ -d "$CACHE_DIR" ]; then
    mkdir -p "$OUTPUT_DIR/vlc_cache"
    # Copy recent files only (modified in last hour)
    find "$CACHE_DIR" -type f -mmin -60 -exec cp {} "$OUTPUT_DIR/vlc_cache/" \; 2>/dev/null || true
    CACHE_FILE_COUNT=$(ls "$OUTPUT_DIR/vlc_cache/" 2>/dev/null | wc -l)
    echo "✓ Copied $CACHE_FILE_COUNT recent cache files"
fi

# Create a summary file with key information
echo "Creating verification summary..."
cat > "$OUTPUT_DIR/task_summary.txt" << EOF
Resume Position Recovery Task - Export Summary
================================================
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Configuration:
--------------
qt-continue: $QT_CONTINUE
Expected values: 0 (ask) or 1 (always) for resume enabled
Current state: $([ "$QT_CONTINUE" = "2" ] && echo "DISABLED (never resume)" || echo "ENABLED")

Media Library:
--------------
XSPF entries: $ENTRY_COUNT
Database: $([ -f "$ML_DB" ] && echo "found" || echo "not found")

Target:
-------
Video: /home/ga/Videos/documentary_urban_planning.mp4
Target position: 47:00 (2820 seconds ± 30 seconds)
Acceptable range: 2790-2850 seconds

Files exported:
---------------
$(ls -lh "$OUTPUT_DIR" 2>/dev/null | tail -n +2 | awk '{print $9, "-", $5}' || echo "No files")
EOF

cat "$OUTPUT_DIR/task_summary.txt"

# Close VLC if still running
if is_vlc_running; then
    echo ""
    echo "Closing VLC..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
    fi
fi

# Create completion marker
echo "$(date -u +"%Y-%m-%d %H:%M:%S UTC")" > "$OUTPUT_DIR/resume_task_completed.txt"

echo ""
echo "✓ Export complete: $OUTPUT_DIR"
echo "=== Export Complete ==="