#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Reaction GIF Result ==="

# Check for the expected GIF file
EXPECTED_GIF="/home/ga/Videos/exports/reaction.gif"
GIF_FOUND="false"

if [ -f "$EXPECTED_GIF" ]; then
    echo "✅ Reaction GIF found: $EXPECTED_GIF"
    GIF_FOUND="true"
    ls -lh "$EXPECTED_GIF"
    
    # Copy to standard location for verification
    cp "$EXPECTED_GIF" /tmp/vlc_reaction.gif
    
    # Get basic file info
    file "$EXPECTED_GIF" || true
else
    echo "⚠️ Expected GIF not found at: $EXPECTED_GIF"
    
    # Look for any recently created GIF in exports directory
    EXPORT_DIR="/home/ga/Videos/exports"
    if [ -d "$EXPORT_DIR" ]; then
        echo "Searching for recent GIF files in $EXPORT_DIR..."
        RECENT_GIF=$(find "$EXPORT_DIR" -name "*.gif" -type f -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_GIF" ]; then
            echo "Found recent GIF: $RECENT_GIF"
            GIF_FOUND="true"
            cp "$RECENT_GIF" /tmp/vlc_reaction.gif
            ls -lh "$RECENT_GIF"
        fi
    fi
    
    # Check if GIF was saved to default VLC locations
    if [ "$GIF_FOUND" = "false" ]; then
        echo "Checking common VLC output locations..."
        for search_dir in "/home/ga/Videos" "/home/ga" "/tmp"; do
            FOUND_GIF=$(find "$search_dir" -maxdepth 2 -name "*.gif" -type f -mmin -10 2>/dev/null | head -1)
            if [ -n "$FOUND_GIF" ]; then
                echo "Found GIF in $search_dir: $FOUND_GIF"
                GIF_FOUND="true"
                cp "$FOUND_GIF" /tmp/vlc_reaction.gif
                break
            fi
        done
    fi
fi

# Create result metadata JSON
if [ "$GIF_FOUND" = "true" ] && [ -f "/tmp/vlc_reaction.gif" ]; then
    FILE_SIZE=$(stat -c%s /tmp/vlc_reaction.gif)
    FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1048576" | bc)
    
    # Try to get GIF info using ffprobe
    GIF_INFO=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames,r_frame_rate -show_entries format=duration -of json /tmp/vlc_reaction.gif 2>/dev/null || echo '{}')
    
    cat > /tmp/vlc_gif_result.json <<EOF
{
    "gif_found": true,
    "file_size_bytes": $FILE_SIZE,
    "file_size_mb": $FILE_SIZE_MB,
    "gif_info": $GIF_INFO
}
EOF
    
    echo "✅ GIF result metadata saved"
    cat /tmp/vlc_gif_result.json
else
    cat > /tmp/vlc_gif_result.json <<EOF
{
    "gif_found": false,
    "file_size_bytes": 0,
    "file_size_mb": 0,
    "gif_info": {}
}
EOF
    echo "❌ No GIF file found to export"
fi

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

# Kill any remaining VLC processes
kill_vlc ga || true

# Create completion marker
echo "$(date)" > /tmp/vlc_gif_completed.txt
echo "Create reaction GIF task completed" >> /tmp/vlc_gif_completed.txt
echo "GIF found: $GIF_FOUND" >> /tmp/vlc_gif_completed.txt

echo "=== Export Complete ==="