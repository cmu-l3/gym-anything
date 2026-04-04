#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enumerate Codec Support Result ==="

# Check for codec support file
TARGET_FILE="/home/ga/Documents/vlc_info/codecs_supported.txt"

if [ -f "$TARGET_FILE" ]; then
    echo "✅ Codec support file found: $TARGET_FILE"
    
    # Show file stats
    FILE_SIZE=$(stat -f%z "$TARGET_FILE" 2>/dev/null || stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0")
    LINE_COUNT=$(wc -l < "$TARGET_FILE" || echo "0")
    
    echo "File size: $FILE_SIZE bytes"
    echo "Line count: $LINE_COUNT lines"
    
    # Copy to /tmp for verification
    cp "$TARGET_FILE" /tmp/vlc_codec_list.txt
    
    # Show first 30 lines as preview
    echo ""
    echo "=== File Preview (first 30 lines) ==="
    head -n 30 "$TARGET_FILE" || true
    echo "=== End Preview ==="
    
else
    echo "⚠️ Codec support file not found at expected location: $TARGET_FILE"
    
    # Check if any file was created in the directory
    INFO_DIR="/home/ga/Documents/vlc_info"
    if [ -d "$INFO_DIR" ]; then
        echo "Contents of $INFO_DIR:"
        ls -lah "$INFO_DIR" || true
        
        # Look for any recently created text files
        RECENT_FILE=$(find "$INFO_DIR" -type f -name "*.txt" -mmin -10 2>/dev/null | head -1)
        
        if [ -n "$RECENT_FILE" ]; then
            echo "Found recent file: $RECENT_FILE"
            cp "$RECENT_FILE" /tmp/vlc_codec_list.txt || true
        fi
    fi
fi

# Close any VLC instances (if agent used GUI approach)
if is_vlc_running; then
    echo "VLC is running, closing..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        kill_vlc ga || true
    fi
fi

# Close terminal if still open
TERM_PID=$(pgrep -u ga xfce4-terminal 2>/dev/null || echo "")
if [ -n "$TERM_PID" ]; then
    echo "Closing terminal..."
    kill $TERM_PID 2>/dev/null || true
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_codec_enum_completed.txt
echo "Codec enumeration task completed" >> /tmp/vlc_codec_enum_completed.txt

# Write summary JSON for debugging
cat > /tmp/vlc_codec_enum_summary.json <<EOF
{
    "target_file": "$TARGET_FILE",
    "file_exists": $([ -f "$TARGET_FILE" ] && echo "true" || echo "false"),
    "file_size": $([ -f "$TARGET_FILE" ] && stat -c%s "$TARGET_FILE" 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Summary saved to /tmp/vlc_codec_enum_summary.json"
cat /tmp/vlc_codec_enum_summary.json

echo "=== Export Complete ==="