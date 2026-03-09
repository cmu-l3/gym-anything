#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Compare Subtitle Versions Result ==="

# Check for selected subtitle file
SELECTED_FILE="/home/ga/Videos/selected_subtitle.srt"

if [ -f "$SELECTED_FILE" ]; then
    echo "✅ Selected subtitle found: $SELECTED_FILE"
    cp "$SELECTED_FILE" /tmp/vlc_selected_subtitle.srt
    echo "Content preview:"
    head -n 10 "$SELECTED_FILE"
    echo "File size: $(wc -c < "$SELECTED_FILE") bytes"
else
    echo "⚠️ Selected subtitle not found at expected location"
    
    # Look for any recently modified subtitle files (not in subtitles dir)
    RECENT_SRT=$(find /home/ga/Videos -maxdepth 1 -name "*.srt" -type f -mmin -10 2>/dev/null | head -1)
    
    if [ -n "$RECENT_SRT" ]; then
        echo "Found recent subtitle file: $RECENT_SRT"
        cp "$RECENT_SRT" /tmp/vlc_selected_subtitle.srt
    else
        echo "No recent subtitle files found"
        # Create empty file to indicate no selection
        touch /tmp/vlc_selected_subtitle.srt
    fi
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

# Create result summary
cat > /tmp/vlc_subtitle_compare_result.json <<EOF
{
    "selected_file_exists": $([ -f "$SELECTED_FILE" ] && echo "true" || echo "false"),
    "file_size": $([ -f "$SELECTED_FILE" ] && wc -c < "$SELECTED_FILE" || echo "0"),
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "✅ Result saved to /tmp/vlc_subtitle_compare_result.json"
cat /tmp/vlc_subtitle_compare_result.json

echo "$(date)" > /tmp/vlc_subtitle_compare_completed.txt
echo "Subtitle comparison task completed" >> /tmp/vlc_subtitle_compare_completed.txt

echo "=== Export Complete ==="