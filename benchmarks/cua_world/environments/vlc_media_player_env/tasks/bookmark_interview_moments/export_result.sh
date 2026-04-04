#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bookmark Interview Moments Result ==="

# Initialize result tracking
BOOKMARKS_FOUND="false"
BOOKMARK_COUNT=0

# Query VLC RC interface for current playback state before closing
if is_vlc_running; then
    echo "Querying VLC RC interface before closing..."
    
    # Get current status
    RC_STATUS=$(echo "status" | nc -w 2 localhost 9999 2>/dev/null || echo "")
    if [ -n "$RC_STATUS" ]; then
        echo "VLC status captured"
        echo "$RC_STATUS" > /tmp/vlc_bookmark_status.txt
    fi
fi

# Close VLC gracefully to ensure bookmark data is written
if is_vlc_running; then
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    echo "Closing VLC to flush bookmark data..."
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 3  # Give VLC time to write files
fi

# Ensure VLC is fully closed
kill_vlc ga 2>/dev/null || true
sleep 1

echo "Searching for bookmark files..."

# Search for bookmark files in multiple potential locations
BOOKMARK_LOCATIONS=(
    "/home/ga/.local/share/vlc/ml.xspf"
    "/home/ga/.config/vlc/bookmarks.xspf"
    "/home/ga/.config/vlc/bookmarks/*.xspf"
    "/home/ga/Videos/interview_migration_2024.mp4.xspf"
    "/home/ga/Videos/*.xspf"
    "/home/ga/.local/share/vlc/*.xspf"
)

# Find most recent bookmark-related files
for pattern in "${BOOKMARK_LOCATIONS[@]}"; do
    for file in $pattern 2>/dev/null; do
        if [ -f "$file" ]; then
            echo "Found potential bookmark file: $file"
            
            # Check if file was modified recently (within last 10 minutes)
            if [ -n "$(find "$file" -mmin -10 2>/dev/null)" ]; then
                echo "  ✅ Recently modified: $file"
                
                # Copy to /tmp for verification
                cp "$file" "/tmp/vlc_bookmark_$(basename "$file")" 2>/dev/null || true
                
                # Count bookmarks in XSPF file
                if grep -q "<track>" "$file" 2>/dev/null; then
                    TRACKS=$(grep -c "<track>" "$file" 2>/dev/null || echo "0")
                    echo "  Found $TRACKS tracks in file"
                    BOOKMARK_COUNT=$((BOOKMARK_COUNT + TRACKS))
                    BOOKMARKS_FOUND="true"
                fi
            fi
        fi
    done
done

# Copy media library (might contain bookmarks)
if [ -f "/home/ga/.local/share/vlc/ml.xspf" ]; then
    echo "Copying VLC media library..."
    cp "/home/ga/.local/share/vlc/ml.xspf" /tmp/vlc_bookmark_ml.xspf || true
fi

# Copy any XSPF files in Videos directory
find /home/ga/Videos -name "*.xspf" -mmin -10 -exec cp {} /tmp/ \; 2>/dev/null || true

# Check VLC config for bookmark-related settings
VLC_RC="/home/ga/.config/vlc/vlcrc"
if [ -f "$VLC_RC" ]; then
    echo "Checking VLC config for bookmark settings..."
    grep -i "bookmark\|chapter" "$VLC_RC" > /tmp/vlc_bookmark_config.txt 2>/dev/null || echo "No bookmark config found" > /tmp/vlc_bookmark_config.txt
fi

# Create summary result file
cat > /tmp/vlc_bookmark_result.json <<EOF
{
    "bookmarks_found": $BOOKMARKS_FOUND,
    "bookmark_count": $BOOKMARK_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Bookmark search results saved"
cat /tmp/vlc_bookmark_result.json

# List all exported files
echo ""
echo "Exported files for verification:"
ls -lh /tmp/vlc_bookmark* 2>/dev/null || echo "  (no bookmark files found)"

# Create completion marker
echo "$(date)" > /tmp/vlc_bookmark_completed.txt
echo "Task completed - bookmark count: $BOOKMARK_COUNT" >> /tmp/vlc_bookmark_completed.txt

echo "=== Export Complete ==="