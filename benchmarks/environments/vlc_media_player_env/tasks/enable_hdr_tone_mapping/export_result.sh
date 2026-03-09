#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Enable HDR Tone Mapping Result ==="

# Close VLC to ensure config is written to disk
if is_vlc_running; then
    echo "Closing VLC to save configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Close via keyboard shortcut
    safe_xdotool ga :1 key --delay 200 ctrl+q
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        echo "Force closing VLC..."
        kill_vlc ga
        sleep 1
    fi
fi

# Wait for config to be written
sleep 1

# Copy VLC config file
VLC_RC="/home/ga/.config/vlc/vlcrc"

if [ -f "$VLC_RC" ]; then
    echo "✅ VLC config found, copying..."
    cp "$VLC_RC" /tmp/vlc_hdr_config.txt
    
    # Show relevant config sections for debugging
    echo ""
    echo "=== VLC Configuration (relevant sections) ==="
    grep -E "video-filter|vout-filter|tone-mapping|adjust" "$VLC_RC" || echo "No tone mapping settings found"
    echo "==========================================="
    echo ""
else
    echo "⚠️ VLC config not found at $VLC_RC"
    touch /tmp/vlc_hdr_config.txt
fi

# Create completion marker
echo "$(date)" > /tmp/vlc_hdr_completed.txt
echo "HDR tone mapping task completed" >> /tmp/vlc_hdr_completed.txt

# Export video info for debugging
if command -v ffprobe &> /dev/null && [ -f "/home/ga/Videos/hdr_test_vacation.mp4" ]; then
    echo "Exporting video metadata..."
    ffprobe -v error -show_streams -show_format \
        -select_streams v:0 \
        "/home/ga/Videos/hdr_test_vacation.mp4" \
        > /tmp/vlc_hdr_video_info.txt 2>&1 || true
fi

echo "✅ Export complete"
echo ""
echo "Exported files:"
echo "  - /tmp/vlc_hdr_config.txt (VLC configuration)"
echo "  - /tmp/vlc_hdr_completed.txt (completion marker)"
echo "  - /tmp/vlc_hdr_video_info.txt (video metadata)"

echo "=== Export Complete ==="